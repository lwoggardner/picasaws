require 'thor'
require 'find'
require 'picasaws/album'
require 'picasaws/auth'

module PicasaWS

    class Application < Thor

        desc "sync directory", "Sync directory with picasaweb"
        option :verbose, :aliases => "v", :type => :boolean
        option :ask, :type => :boolean, :desc => "confirm actions"
        option :dry_run, :type => :boolean
        def sync(dir)

            Dir.glob("#{dir}/*/").each do |dir_path|
                album = Album.find_directory(dir_path)
                debug("Found album #{album.id} at #{dir_path}")
                Dir.glob("#{dir_path}/*") do |file_path|
                    Image.find_file(album.id,file_path)
                end
            end


            picasa.album.list.albums.each do |web_album|
                # picasa.album.delete(web_album.id) if web_album.title =~ /RPS/ 
                album = Album.find_album(web_album)
                if album
                    debug("Processing PWS album #{album.id}")
                    #We have to "show" to get the photo lists
                    web_album = picasa.album.show(web_album.id)
                    web_album.photos.each do |web_photo|
                        Image.find_photo(album.id,web_photo)
                    end
                else
                    debug("Skipping non PWS album #{web_album.title}")
                end
            end

            info("Found #{Album.set.size} albums and #{Image.set.size} images")

            apply(Album,:create,:sync)

            apply(Image,:create,:sync)

            apply(Album,:delete)

            apply(Image,:delete)

        end

        no_tasks do

            def picasa
                @picasa ||= PicasaWS.client
            end

            def info(*args)
                say(*args)
            end

            def debug(*args)
                say(*args) if options[:verbose]
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
        end
    end
end

