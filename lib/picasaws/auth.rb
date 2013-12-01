require 'picasa'

module PicasaWS

    def self.client()
        client = Picasa::Client.new(:user_id => "lwoggardner", :password => ENV["GPASS"])

        client
    rescue Picasa::ForbiddenError
        puts "You have the wrong user_id or password."
    end
end
