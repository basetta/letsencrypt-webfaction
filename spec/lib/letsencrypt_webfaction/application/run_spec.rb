require 'acme-client'
require 'xmlrpc/client'
require 'letsencrypt_webfaction/application/run'
require 'letsencrypt_webfaction/options'

module LetsencryptWebfaction
  RSpec.describe Application::Run do
    PUBLIC_DIR = TEMP_DIR.join('example').freeze
    before :each do
      FileUtils.mkdir_p PUBLIC_DIR
    end

    before :each do
      stub_request(:post, 'https://wfserverapi.example.com/')
        .with(body: "<?xml version=\"1.0\" ?><methodCall><methodName>login</methodName><params><param><value><string>myusername</string></value></param><param><value><string>mypassword</string></value></param><param><value><string>myservername</string></value></param><param><value><i4>2</i4></value></param></params></methodCall>\n")
        .to_return(status: 200, body: fixture('login_response.xml'))
      stub_request(:post, 'https://wfserverapi.example.com/')
        .with(body: "<?xml version=\"1.0\" ?><methodCall><methodName>list_certificates</methodName><params><param><value><string>oz7e1xz9r0mf0wgue22hsj8tgkhqyo74</string></value></param></params></methodCall>\n")
        .to_return(status: 200, body: fixture('list_certificates_response.xml'))
      stub_request(:post, 'https://wfserverapi.example.com/')
        .with(body: "<?xml version=\"1.0\" ?><methodCall><methodName>create_certificate</methodName><params><param><value><string>oz7e1xz9r0mf0wgue22hsj8tgkhqyo74</string></value></param><param><value><string>www_example_com</string></value></param><param><value><string>CERTIFICATE</string></value></param><param><value><string>PRIVATE KEY</string></value></param><param><value><string>CHAIN!</string></value></param></params></methodCall>\n")
        .to_return(status: 200, body: fixture('create_certificate_response.xml'))
    end

    let(:args) { [] }
    let(:application) { described_class.new(args) }

    describe '#run!' do
      before :each do
        # Set up doubles to avoid actual verification and communication with LE.
        authorization = double('authorization', verify_status: 'valid')
        challenge = double('challenge', filename: 'challenge1.txt', file_content: 'woohoo!', request_verification: nil, authorization: authorization)
        certificate = double('certificate', to_pem: 'CERTIFICATE', chain_to_pem: 'CHAIN!', fullchain_to_pem: 'FULLCHAIN!!')
        allow(certificate).to receive_message_chain(:request, :private_key, to_pem: 'PRIVATE KEY')
        client = double('client', new_certificate: certificate)
        allow(client).to receive_message_chain(:authorize, http01: challenge)
        allow(client).to receive_message_chain(:register, agree_terms: nil)
        allow(Acme::Client).to receive(:new) { client }
      end

      context 'with missing configuration file' do
        it 'outputs error message' do
          expect do
            application.run!
          end.to raise_error(AppExitError).and output(/The configuration file is missing/).to_stderr
        end
      end

      context 'with invalid configuration file', :uses_tmp_dir do
        before :each do
          FileUtils.cp FIXTURE_DIR.join('test_invalid_config.toml'), TEMP_DIR.join('letsencrypt_webfaction.toml')
        end

        it 'outputs configuration error message' do
          expect do
            application.run!
          end.to raise_error(AppExitError).and output(/The configuration file has an error/).to_stderr
        end
      end

      context 'with invalid credentials', :uses_tmp_dir do
        before :each do
          stub_request(:post, 'https://wfserverapi.example.com/')
            .with(body: "<?xml version=\"1.0\" ?><methodCall><methodName>login</methodName><params><param><value><string>myusername</string></value></param><param><value><string>mypassword</string></value></param><param><value><string>myservername</string></value></param><param><value><i4>2</i4></value></param></params></methodCall>\n")
            .to_raise(XMLRPC::FaultException.new(1, 'LoginError'))
        end

        before :each do
          FileUtils.cp FIXTURE_DIR.join('test_valid_config.toml'), TEMP_DIR.join('letsencrypt_webfaction.toml')
        end

        it 'outputs login error message' do
          expect do
            application.run!
          end.to raise_error(AppExitError).and output(/Login failed/).to_stderr
        end
      end

      describe 'cert issuance', :uses_tmp_dir do
        before :each do
          stub_request(:post, 'https://wfserverapi.example.com/')
            .with(body: "<?xml version=\"1.0\" ?><methodCall><methodName>login</methodName><params><param><value><string>myusername</string></value></param><param><value><string>mypassword</string></value></param><param><value><string>myservername</string></value></param><param><value><i4>2</i4></value></param></params></methodCall>\n")
            .to_return(status: 200, body: fixture('login_response.xml'))
        end

        before :each do
          FileUtils.cp FIXTURE_DIR.join('test_valid_config.toml'), TEMP_DIR.join('letsencrypt_webfaction.toml')
        end

        before :each do
          # Low security key for test speed and size.
          FileUtils.mkdir_p Options.default_config_path
          Options.default_config_path.join('account_key.pem').write(OpenSSL::PKey::RSA.new(256).to_pem)
        end

        let(:expiration) { '2017-01-30' }
        let(:domains) { [] }
        let(:name) { 'myname' }

        before :each do
          stub_request(:post, 'https://wfserverapi.example.com/')
            .with(body: "<?xml version=\"1.0\" ?><methodCall><methodName>list_certificates</methodName><params><param><value><string>oz7e1xz9r0mf0wgue22hsj8tgkhqyo74</string></value></param></params></methodCall>\n")
            .to_return(status: 200, body: <<-RESPONSE
  <?xml version='1.0'?>
  <methodResponse>
  	<params>
  		<param>
  			<value>
  				<array>
  					<data>
  						<value>
  							<struct>
  								<member>
  									<name>private_key</name>
  									<value>
  										<string>-----BEGIN RSA PRIVATE KEY-----
  PRIVATE_KEY
  -----END RSA PRIVATE KEY-----</string>
  									</value>
  								</member>
  								<member>
  									<name>intermediates</name>
  									<value>
  										<string>-----BEGIN CERTIFICATE-----
  INTERMEDIATE CERT
  -----END CERTIFICATE-----</string>
  									</value>
  								</member>
  								<member>
  									<name>name</name>
  									<value>
  										<string>#{name}</string>
  									</value>
  								</member>
  								<member>
  									<name>certificate</name>
  									<value>
  										<string>-----BEGIN CERTIFICATE-----
  CERTIFICATE
  -----END CERTIFICATE-----</string>
  									</value>
  								</member>
  								<member>
  									<name>expiry_date</name>
  									<value>
  										<string>#{expiration}</string>
  									</value>
  								</member>
  								<member>
  									<name>domains</name>
  									<value>
                      <string>#{domains.join(',')}</string>
  									</value>
  								</member>
  								<member>
  									<name>id</name>
  									<value>
  										<int>1234</int>
  									</value>
  								</member>
  							</struct>
  						</value>
  					</data>
  				</array>
  			</value>
  		</param>
  	</params>
  </methodResponse>
  RESPONSE
                      )
        end

        context 'with previously unissued cert' do
          let(:expiration) { '2017-01-30' }
          let(:domains) { ['test.example.com'] }
          let(:name) { 'mynewcert' }

          before :each do
            stub_request(:post, 'https://wfserverapi.example.com/')
              .with(body: "<?xml version=\"1.0\" ?><methodCall><methodName>create_certificate</methodName><params><param><value><string>oz7e1xz9r0mf0wgue22hsj8tgkhqyo74</string></value></param><param><value><string>myname</string></value></param><param><value><string>CERTIFICATE</string></value></param><param><value><string>PRIVATE KEY</string></value></param><param><value><string>CHAIN!</string></value></param></params></methodCall>\n")
              .to_return(status: 200, body: fixture('create_certificate_response.xml'), headers: {})
          end

          it 'issues cert' do
            expect { application.run! }.to output(/Issuing myname for the first time/).to_stdout
          end
        end

        context 'with still valid cert' do
          let(:expiration) { '2017-01-30' }
          let(:domains) { ['test.example.com', 'test1.example.com'] }

          it 'skips cert' do
            Timecop.freeze(Date.new(2017, 1, 1)) do
              expect { application.run! }.to output(/29 days until expiration of myname\. Skipping\.\.\./).to_stdout
            end
          end
        end

        context 'with expires shortly cert' do
          let(:expiration) { '2017-01-30' }
          let(:domains) { ['test.example.com', 'test1.example.com'] }

          before :each do
            stub_request(:post, 'https://wfserverapi.example.com/')
              .with(body: "<?xml version=\"1.0\" ?><methodCall><methodName>update_certificate</methodName><params><param><value><string>oz7e1xz9r0mf0wgue22hsj8tgkhqyo74</string></value></param><param><value><string>myname</string></value></param><param><value><string>CERTIFICATE</string></value></param><param><value><string>PRIVATE KEY</string></value></param><param><value><string>CHAIN!</string></value></param></params></methodCall>\n")
              .to_return(status: 200, body: fixture('create_certificate_response.xml'), headers: {})
          end

          it 'renews cert' do
            Timecop.freeze(Date.new(2017, 1, 29)) do
              expect { application.run! }.to output(/1 days until expiration of myname\. Renewing\.\.\./).to_stdout
            end
          end
        end

        context 'with different domains cert' do
          let(:expiration) { '2017-01-30' }
          let(:domains) { ['test.example.com', 'test2.example.com'] }

          before :each do
            stub_request(:post, 'https://wfserverapi.example.com/')
              .with(body: "<?xml version=\"1.0\" ?><methodCall><methodName>update_certificate</methodName><params><param><value><string>oz7e1xz9r0mf0wgue22hsj8tgkhqyo74</string></value></param><param><value><string>myname</string></value></param><param><value><string>CERTIFICATE</string></value></param><param><value><string>PRIVATE KEY</string></value></param><param><value><string>CHAIN!</string></value></param></params></methodCall>\n")
              .to_return(status: 200, body: fixture('create_certificate_response.xml'), headers: {})
          end

          it 'reissues cert' do
            Timecop.freeze(Date.new(2017, 1, 1)) do
              expect { application.run! }.to output(/Reissuing myname due to a change in the domain list/).to_stdout
            end
          end
        end
      end

      # it 'writes validation file' do
      #   expect do
      #     application.run!
      #   end.to output(/Your new certificate is now created and installed/).to_stdout
      #
      #   expect(PUBLIC_DIR.join('challenge1.txt')).to exist
      # end
      #
      # context 'with quiet param' do
      #   let(:args) { super() + ['--quiet'] }
      #
      #   it 'does not output message' do
      #     expect do
      #       application.run!
      #     end.to_not output(/Your new certificate is now created and installed/).to_stdout
      #   end
      # end
      #
      # context 'with invalid credentials' do
      #   before :each do
      #     stub_request(:post, 'https://wfserverapi.example.com/')
      #       .with(body: "<?xml version=\"1.0\" ?><methodCall><methodName>login</methodName><params><param><value><string>myusername</string></value></param><param><value><string>mypassword</string></value></param><param><value><string>myservername</string></value></param><param><value><i4>2</i4></value></param></params></methodCall>\n")
      #       .to_raise(XMLRPC::FaultException.new(1, 'LoginError'))
      #   end
      #
      #   it 'exits due to invalid credentials' do
      #     expect do
      #       application.run!
      #     end.to output(/Login failed/).to_stderr.and raise_error SystemExit
      #   end
      # end
    end
  end
end
