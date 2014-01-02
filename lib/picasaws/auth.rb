require 'picasa'

module PicasaWS

    CLIENT_ID = "151560738048.apps.googleusercontent.com"

    # For installed apps and devices this is (obviously) not intended to be secret
    CLIENT_SECRET =  "4uQUTwPqBcTdOSlYGYoAl1ma"
    OAUTH_SCOPE = "http://picasaweb.google.com/data/"

    def self.client(params = {})
        params = { :user_id => "default" }.merge!(params)
        Picasa::Client.new(params)
    end

end
