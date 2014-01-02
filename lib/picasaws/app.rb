require 'thor'
require 'picasaws/album'
require 'picasaws/auth'
require 'picasaws/google_oauth'
require 'picasaws/config'
require 'picasaws/optional_gems'

module PicasaWS

    class Application < Thor


        class_option :config, :aliases => "c", :type => :string, :desc => "path to configuration file"
        class_option :verbose, :aliases => "v", :type => :boolean

        desc "show DIR", "list album structure for DIR as it will appear in picasa"
        def show(dir)
            @verbose = true
            do_config
            Album.load_directory(dir)
        end

        desc "fuse DIR MOUNTPOINT", "start fuse filesystem at MOUNTPOINT that mimics how albums in DIR would appear in picasa"
        option :transform_dir, :aliases => 't', :desc => "directory to hold transformed files"
        def fuse(dir,mountpoint)

            OptionalGems.require('rfusefs') unless defined?(FuseFS)
            require 'fusefs/pathmapper'

            do_config

            Album.load_directory(dir)

            transform_dir = options[:transform_dir] || Dir.mktmpdir("picasaws") 
            fs = FuseFS::PathMapperFS.new(use_raw_file_access: true)

            t = Thread.new() do
                begin
                    Album.set().each_value do |album|
                        args = album.to_fuse
                        debug(*args)
                        fs.mkdir(*args)
                    end

                    Image.set().each_value do |image|
                        args = image.to_fuse(transform_dir)
                        debug(*args)
                        fs.map_file(*args)
                    end
                rescue Exception => ex
                    puts ex,ex.backtrace.join("\n")
                end
            end
            FuseFS.start(fs,mountpoint)

            FileUtils.rm_r(transform_dir) unless options[:transform_dir]
        end 

        desc "auth", "Setup google authentication"
        option :token_path, :aliases => "t", :type => :string, :desc => "path to store google authentication token", :default => "~/.picasaws.token"
        def auth()
            do_auth()

            say "Success!"
        end

        desc "sync", "Sync directory with picasaweb"
        option :ask, :type => :boolean, :desc => "confirm actions"
        option :dry_run, :type => :boolean
        option :local_path, :aliases => "l", :type => :string, :desc => "path to store information about previously synced images"
        option :token_path, :aliases => "t", :type => :string, :desc => "path to store google authentication token", :default => "~/.picasaws.token"
        option :user_id, :aliases => "u", :type => :string, :desc => "login with explicit user and password (prompted)"
        def sync(dir)

            do_auth() 

            do_config()

            local_path = options[:local_path]

            # also loads Image files, also counts images
            Album.load_directory(dir)

            # only loads album details
            Album.load_web(picasa)

            #without local load, all images appear will appear to be missing in picasa
            #and will trigger a load_album
            if local_path && File.exists?(local_path)
                Image.load_local(local_path)
            else
                debug "No local_path #{local_path}" 
            end

            info("Syncing #{Album.set.size} albums")

            # if the photo count and image count don't match, then we need to find out which
            # images have to be deleted
            apply(Album,:load_photos)

            # If any photos in an album are not synchronised is required and the album has not been loaded
            apply(Image,:load_photos)

            Image.store_local(local_path) if local_path

            apply(Album,:create,:sync)

            apply(Image,:create,:sync)

            apply(Album,:delete)

            apply(Image,:delete)
            #TODO this will retain deleted images - probably should filter them out
            Image.store_local(local_path) if local_path
        end

        no_tasks do

            def picasa
                @picasa 
            end

            def info(*args)
                say(*args)
            end

            def debug(*args)
                say(*args) if options[:verbose] || @verbose
            end

            def apply(klass, *actions)
                debug "Processing #{actions} for #{klass}"
                klass.set.values.each do |obj|
                    action,message = obj.action
                    if actions.include?(action)
                        begin
                            case
                            when options[:ask]
                                obj.send(action,picasa) if :load_photos == action || yes?("#{message}\n Continue (y/n)?")
                            when options[:dry_run]
                                info(message)
                                obj.send(action,picasa) if :load_photos == action
                            else
                                info(message)
                                obj.send(action,picasa)
                            end
                        rescue Picasa::ResponseError => ex
                            info(ex.message)
                        end
                    else
                        debug("Skipping #{action} for #{obj.inspect}")
                    end
                end
            end

            def do_config()
                config = options[:config]
                load config if config
            end

            def do_auth()
                if options[:user_id]
                    password = ask("Password:",:echo => false)
                    @picasa = PicasaWS.client(:user_id => options[:user_id], :password => password)
                else
                    auth_client = GoogleOAuth::Client.new(PicasaWS::CLIENT_ID,PicasaWS::CLIENT_SECRET)

                    token_path = File.expand_path(options[:token_path])

                    result = auth_client.auth_device(PicasaWS::OAUTH_SCOPE,:refresh_token_path => token_path) do |response|
                        case response
                        when GoogleOAuth::Codes
                            url = response.verification_url
                            code = response.user_code
                            say "Google authentication\n  Please visit #{url}\n  and enter code \"#{code}\"\n"
                        else
                            say "Waiting ... #{response.message}"
                        end
                    end

                    raise "Authentication failed" unless result

                    @picasa = PicasaWS.client(:authorization_header => result.auth_header)
                end
            end
        end #no_tasks
    end
end

