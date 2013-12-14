require 'thor'
require 'find'
require 'picasaws/album'
require 'picasaws/auth'
require 'picasaws/config'
require 'picasaws/optional_gems'

module PicasaWS

    class Application < Thor
        class_option :config, :aliases => "c", :type => :string, :desc => "path to configuration file"
        class_option :verbose, :aliases => "v", :type => :boolean

        desc "show DIR", "list album structure for DIR as it will appear in picasa"
        def show(dir)
            @verbose = true
            load_albums(dir)
        end

        desc "fuse DIR MOUNTPOINT", "start fuse filesystem at MOUNTPOINT that mimics how albums in DIR would appear in picasa"
        option :transform_dir, :aliases => 't', :desc => "directory to hold transformed files"
        def fuse(dir,mountpoint)

            OptionalGems.require('rfusefs') unless defined?(FuseFS)
            require 'fusefs/pathmapper'

            load_albums(dir)

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

        desc "sync", "Sync directory with picasaweb"
        option :ask, :type => :boolean, :desc => "confirm actions"
        option :dry_run, :type => :boolean
        def sync(dir)

            load_albums(dir)

            picasa.album.list.albums.each do |web_album|
                # picasa.album.delete(web_album.id) if web_album.title =~ /RPS/ 
                album = Album.from_album(web_album)
                if album
                    debug("Processing #{Config.sync_id} album #{album.id}")
                    #We have to "show" to get the photo lists
                    web_album = picasa.album.show(web_album.id)
                    web_album.photos.each do |web_photo|
                        Image.from_photo(album.id,web_photo)
                    end
                else
                    debug("Skipping non #{Config.sync_id} album #{web_album.title}")
                end
            end

            info("Found #{Album.set.size} albums and #{Image.set.size} images")

            apply(Album,:create,:sync)

            apply(Image,:create,:sync)

            apply(Album,:delete)

            apply(Image,:delete)

        end

        no_tasks do

            def load_albums(dir)
                do_config
                require 'find'

                album=nil
                Find.find(dir) do |file|
                    if File.directory?(file)
                        #Exclude hidden directories
                        album = Album.from_directory(file)
                        if album
                            debug("Album #{album.id} at #{file}")
                            debug("  #{album.dir_data}")
                        end
                    elsif File.file?(file) && album
                        image = Image.from_file(album.id,file)
                        if image
                            debug("  Image #{album.id},#{image.id} #{file}")
                            debug("        #{image.file_data}")
                        end
                    end
                end
            end

            def picasa
                @picasa ||= PicasaWS.client
            end

            def info(*args)
                say(*args)
            end

            def debug(*args)
                say(*args) if options[:verbose] || @verbose
            end

            def apply(klass, *actions)
                klass.set.each_value do |obj|
                    action,message = obj.action
                    if actions.include?(action)
                        case
                        when options[:ask]
                            obj.send(action,picasa) if yes?("#{message}\n Continue (y/n)?")
                        when options[:dry_run]
                            info(message)
                        else
                            info(message)
                            obj.send(action,picasa)
                        end
                    end
                end
            end

            def do_config()
                config = options[:config]
                load config if config
            end
        end
    end
end

