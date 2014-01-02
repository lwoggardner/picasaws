require 'oauth2' #oauth2-client gem, not the oauth2 gem!!
require 'json'
module GoogleOAuth 

    # @!visibility private
    module AttrParsed
        # @!visibility private
        def self.included(base)
            base.extend(ClassMethods)
        end

        # @!visibility private
        module ClassMethods
            def attr_parsed(*attributes,&block)
                attributes.each do |attr|
                    define_method(attr.to_sym) do
                        value = @parsed_body[attr.to_s]
                        if block then block.call(value) else value end
                    end
                end 
            end
        end

        # @!visibility private
        attr_reader :parsed_body, :parsed_at

        # @!visibility private
        def initialize(response)
            response.value
            @parsed_body = JSON.parse(response.body)
            @parsed_at = Time.now
        end
    end

    # Base Response class, used for errors and messages
    class Response
        # @!visibility private
        include AttrParsed

        # @!attribute [r] error
        #   @return [String] the message
        attr_parsed :error

        alias :message :error

        # @return [true] if error is defined
        def error?
            error && true
        end
    end

    class Codes < Response
        # @!attribute [r] verification_url
        #   @return [String] URL for the user to visit and enter the {#user_code}
        # @!attribute [r] user_code
        #   @return [String] a code to enter into the form at {#verification_url}
        # @!attribute [r] device_code
        #   @return [String] code used to obtain an access token once the user action is completed
        # @!attribute [r] interval
        #   @return [Integer] number of seconds to wait between attempting to get an access token
        # @!attribute [r] expires_in
        #   @return [Integer] number of seconds the codes are valid for. See also {#expired?}
        attr_parsed :verification_url, :device_code, :user_code
        attr_parsed(:interval, :expires_in) { |a| a.to_i }

        # 
        # @return [true] if codes have expired
        def expired?
            Time.now > (parsed_at + expires_in)
        end
    end

    class AccessToken < Response
        # @!attribute [r] access_token
        #   @return [String]
        # @!attribute [r] token_type
        #   @return [String] 
        # @!attribute [r] refresh_token
        #   @return [String] 
        # @!attribute [r] expires_in
        #   @return [Integer] number of seconds the {#access_token} is valid for. See also {#expired?}
        attr_parsed :access_token, :token_type, :refresh_token
        attr_parsed (:expires_in) { |a| a.to_i }

        # 
        # @return [true] if the access code has expired
        def expired?
            Time.now > (parsed_at + expires_in)
        end

        # 
        # @return [String] suitable for using in the "Authorization:" header for API requests
        def auth_header
            "#{token_type} #{access_token}"
        end
    end

    class RefreshedToken < AccessToken

        # The supplied refresh token which is presumaed valid (unless {#error?})
        attr_reader :refresh_token
        
        # @!visibility private
        def initialize(response,refresh_token)
            @refresh_token = refresh_token
            super(response)
        end
    end

    class Client < OAuth2::Client

        # @param [String] client_id
        # @param [String] client_secret
        def initialize(client_id, client_secret)
            super(
                "https://accounts.google.com",client_id,client_secret,
                :device_path => "/o/oauth2/device/code",
                :token_path => "/o/oauth2/token"
            )
        end

        # Implements Googls OAuth 2.0 for Devices
        # See https://developers.google.com/accounts/docs/OAuth2ForDevices
        #
        # If a valid refresh token is supplied it is used to generate an access token and no further user involvement is required
        #
        # If the refresh_token is nil (or file is empty) then a new device code will be generated which is yielded back to the caller
        # to be displayed to the user.  The method then loops until either the device code expires, or the user completes the device
        # authorisation via a browser.
        #
        # @overload authenticate_device(*scopes,params,&block)
        #   @param [Array<String>] scopes list of scopes to authorize
        #   @param [Hash] params specifiying how to handle the refresh token. Exactly one option to be supplied
        #   @option params [String] :refresh_token_path Path to a file in which the refresh token will be stored
        #   @option params [String] :refresh_token The actual refresh token. Caller must take care to reuse appropriately
        #
        # @yield (response) only when the refresh token is not valid and user action is required
        # @yieldparam response [Codes|Response]
        #      * first response is a {Codes} containing verification_url and user_code to display to user
        #      * subsequent reponses are messages to display while waiting for the user action to complete elsewhere - typically
        #        "authorization pending"
        # @yieldreturn [void]
        #
        # @return [AccessToken] response containing access_token and refresh token for future requests
        # @return [nil] if authentication was not successful
        #
        # @example
        #
        #   auth_client = GoogleOAuth::Client.new(MY_APP_ID,MY_APP_SECRET)
        #
        #   result = auth_client.auth_device(MY_OAUTH_SCOPE,:refresh_token_path => token_path) do |response|
        #      case response
        #      when GoogleOAuth::Codes
        #          url = response.verification_url
        #          code = response.user_code
        #          puts "Google authentication\n  Please visit #{url}\n  and enter code \"#{code}\"\n"
        #      else
        #          puts "Waiting ... #{response.message}"
        #      end
        #   end
        #
        #   raise "Auth failed" unless result

        def auth_device(*scopes,&block)
            raise ArgumentError, "Missing scope or refresh_token" if scopes.size < 2

            params = scopes.pop

            raise ArgumentError, "Expecting hash parameter" unless params.respond_to?(:[]) 

            token_path = params[:refresh_token_path]
            refresh_token = params[:refresh_token]

            unless token_path || refresh_token
                raise ArgumentError, "Hash parameter must include either :refresh_token_path or :refresh_token" 
            end

            if token_path
                # Read token and make sure we will be able to write to the file
                if FileTest.size?(token_path) 
                    refresh_token = File.read(token_path)
                    raise "#{token_path} not writable" unless File.writable?(token_path)
                else
                    File.open(token_path,"w+",0600) { |f| nil }
                end
            end

            result = device_flow(scopes,refresh_token,&block)

            if token_path && !result.refresh_token.eql?(refresh_token)
                File.open(token_path,"w+",0600) { |f| f.write(result.refresh_token) } 
            end

            result

        end

        private

        def device_flow(scopes,refresh_token,&block)

            if refresh_token
                response = self.refresh_token.get_token(refresh_token, { :authenticate => :body })
                result = RefreshedToken.new(response,refresh_token)
                return result unless result.error?
            end

            response = device_code.get_code(:params => { :scope => scopes })
            codes = Codes.new(response)

            yield codes

            until codes.expired?

                # TODO protect against interval = 0 
                sleep codes.interval

                response = device_code.get_token(codes.device_code, {:authenticate => :body })

                access_token = AccessToken.new(response)

                if access_token.error?
                    yield access_token
                else
                    return access_token
                end
            end

            # expired
            return nil
        end
    end
end
