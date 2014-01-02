require 'picasa'
require 'picasaws/config'
require 'find'

# Local enhancement to picasa presenter class
#class Picasa::Presenter::Photo < Picasa::Presenter::Base
#    def stream_id
#        @stream_id ||= safe_retrieve(parsed_body,"gphoto$streamId")
#    end
#    def auto_awesome?
#        "synth_auto".eql?(stream_id)
#    end
#end

module PicasaWS
    class Album

        AlbumData = Struct.new(:title, :timestamp, :comment) do
            def self.create(from_hash)
                args = members.collect() { |m| from_hash[m] }
                self.new(*args)
            end
        end

        attr_reader :id, :dir,:album, :dir_data, :album_data, :dir_image_count
        attr_reader :photo_list_loaded

        def self.load_directory(dir)
            album=nil
            Find.find(dir) do |file|
                if File.directory?(file)
                    #Exclude hidden directories
                    album = Album.from_directory(file)
                elsif File.file?(file) && album
                    image = Image.from_file(album.id,file)
                    album.increment_image_count if image
                end
            end
            nil
        end

        def self.load_web(picasa)
            picasa.album.list.albums.each do |web_album|
                self.from_album(web_album)
            end
            nil
        end

        def self.set
            @albums ||= Hash.new() { |h,k| h[k] = Album.new(k)}
        end

        def self.from_directory(dir)
            values = Config.__album_data__(dir)
            id = values[:id]
            if id
                values[:timestamp] = values[:timestamp].to_i if values[:timestamp]           
                values[:title] = values[:title].to_s 
                values[:comment] = values[:comment].to_s 
                self.set[id].set_dir(dir,AlbumData.create(values))
                self.set[id]
            end
        end

        def self.from_album(web_album)
            summary = web_album.summary
            parsed =  summary.match(/\s*\(#{Config.sync_id}:(.+)\)/)
            if parsed
                id = parsed[1]
                title   = web_album.title
                timestamp = web_album.timestamp.to_i
                comment = parsed.pre_match
                self.set[id].set_album(web_album,AlbumData.new(title,timestamp,comment))
                self.set[id] 
            else
                #Not an RPS synced album
                nil
            end
        end

        def initialize(id)
            @id = id
            @dir_image_count = 0
            @photo_list_loaded = false
        end

        def set_dir(dir,data)
            @dir = dir
            @dir_data = data
        end

        def increment_image_count
            @dir_image_count += 1
        end

        def set_album(album,data)
            @album = album
            @album_data = data
        end

        # action required to bring web in line with the file system
        def action()
            case
            when dir.nil? && album.nil? 
                [:ignore_deleted,nil]
            when dir.nil?
                [:delete,"Deleting album #{self}"]
            when album.nil?
                [:create,"Creating album #{self}"]
            when !photo_list_loaded && (dir_image_count != album.numphotos)
                [:load_photos, "Load photo list for #{self}" ]
            when !dir_data.eql?(album_data)
                [:sync, "Synching album data for #{id}\n - dir #{dir_data}\n - web #{album_data}"]
            else
                [:ignore_synced,nil]
            end
        end

        def comment_to_summary
            "#{dir_data.comment} (#{Config.sync_id}:#{id})"
        end

        def create(picasa)
            @album = picasa.album.create(
                :title => dir_data.title,
                :summary => comment_to_summary,
                :timestamp => dir_data.timestamp,
                :access => "private"
            )
            @album_data = dir_data
            @photo_list_loaded = true
            @album
        end

        def load_photos(picasa)
            web_album = picasa.album.show(album.id)
            web_album.photos.each do |web_photo|
                Image.from_photo(id,web_photo)
            end
            @photo_list_loaded = true
        end

        def sync(picasa)
            @album = picasa.album.update(
                album.id,
                :title => dir_data.title,
                :timestamp => dir_data.timestamp,
                :summary => comment_to_summary
            )
            @album_data = dir_data
            @album
        end

        def delete(picasa)
            picasa.album.delete(album.id)
            @album = nil
            @album_data = nil
        end

        def to_fuse
            xattr = {}
            dir_data.each_pair{ |k,v| xattr["user.#{k}"] = v.to_s }
            [ "/#{dir_data.title}" , {:xattr => xattr} ]
        end

        def to_s
            "#{id} #{(dir_data||album_data).title}"
        end

        def inspect
            <<-INSPECT
id=#{id},
  dir=#{dir}, image_count=#{dir_image_count}
  picasa_id=#{album.id if album}, numphotos=#{album.numphotos if album}, photo_list_loaded=#{photo_list_loaded}
  #{dir_data.inspect if dir_data}
  #{album_data.inspect if album_data}
  INSPECT
        end

    end

    class Image
        attr_reader :id, :file, :file_data, :photo, :photo_data, :effect_gifs

        ImageData = Struct.new(:album_id, :timestamp, :caption, :keywords) do
            def self.create(hash)
                args = members.collect() { |m| hash[m] }
                self.new(*args)
            end
        end

        def self.set
            @images ||= Hash.new() { |h,k| h[k] = Image.new(k)}
        end

        # This saves us from making a call to list photos for each album
        # unless an image has changed
        # it must happen after loading albums
        def self.load_local(path)
            images = Marshal.load(File.read(path))
            images.each_pair do |id,photo_data|
                # do not add mages for which the album doesn't exist
                if Album.set[photo_data.album_id]
                    set[id].set_photo(nil,photo_data)
                end
            end
        end

        def self.store_local(path)
            photo_data = self.set.select() { |id,image| image.photo_data }.
                inject({}) { |h,p| id,image = *p; h[id] = image.photo_data; h }
            File.open(path,"w") { |f| f.write(Marshal.dump(photo_data)) }
        end

        # id(title), caption,, keywords and timestamp
        # id should be unique for image data
        def self.from_file(album_id, path)

            values = Config.__file_data__(path)

            id = values[:id]
            if id
                values[:timestamp] = values[:timestamp].to_i if values[:timestamp]
                values[:caption] = values[:caption].to_s 
                values[:keywords] = self.parse_keywords(values[:keywords]) 
                data = ImageData.create(values)
                data.album_id = album_id

                image = self.set[id]
                image.set_file(path, data)
                image
            end
        end

        def self.from_photo(album_id, photo)
            id = photo.title
            timestamp = photo.timestamp.to_i
            comment = photo.summary
            keywords = parse_keywords(photo.media.keywords)
            self.set[id].set_photo(photo,ImageData.new(album_id,timestamp,comment,keywords))
            self.set[id]
        end

        def self.parse_keywords(str)
            return [] unless str
            case str
            when Array
                str.collect { |k| k.to_s }
            else
                str.split(/, */)
            end.sort
        end

        def initialize(id)
            @id = id
            @effect_gifs = []
        end

        def set_file(file,data)
            @file = file
            @file_data = data
        end

        def set_photo(photo,data)
            @photo = photo
            @photo_data = data
        end

        def add_effect_gif(photo)
            @effect_gifs << photo
        end

        # file and file_data
        # photo_data but no photo (album not loaded, or already deleted)
        # photo and photo data (album loaded, file exists)
        def action

            photo_album = Album.set[photo_data.album_id] if photo_data
            file_album = Album.set[file_data.album_id] if file_data

            if photo_data && !photo && photo_album.photo_list_loaded
                #image loaded from cache information does not really exist in picasa anymore
                #but its album still does
                @photo_data = nil
                photo_album = nil
            end

            # my album has been deleted, so I have also been deleted
            if photo_data && photo_album.action == :ignore_deleted
                @photo = nil
                @photo_data = nil
                photo_album = nil
            end

            case
            when !file & !photo_data 
                [:ignore_deleted, nil]
            when file && file_data.eql?(photo_data)
                [:ignore_synced,nil]
            when file && !file_album.album
                # Can't create the image if the destination album hasn't been created
                [:wait_album_create, nil] 
            when (photo_album && !photo_album.photo_list_loaded) || (file_album && !file_album.photo_list_loaded)
                [:load_photos, "Load photo list for #{photo_album.to_s} and #{file_album.to_s}"]
            when !file
                [:delete, "Deleting image #{id} from #{photo_album.to_s}"]
            when !photo
                [:create, "Creating image #{id} in #{file_album.to_s}"]
            else #when !file_data.eql?(photo_data)
                [:sync, "Synchronising image #{id}\n - file #{file_data}\n - web  #{photo_data}"]
            end
        end

        def create(picasa,transform_dir=nil)

            details = { 
                title: id,
                summary: file_data.caption,
                keywords: file_data.keywords.join(","),
                timestamp: file_data.timestamp
            }

            details.merge!(Config.__transform__(file))

            @photo = picasa.photo.create(
                Album.set[file_data.album_id].album.id,
                details
            )
            @photo_data = file_data
            @photo
        end

        def sync(picasa)
            target_album_id = Album.set[file_data.album_id].album.id

            @photo = picasa.photo.update(
                photo.album_id,photo.id,
                :title => id,
                :summary => file_data.caption,
                :keywords => file_data.keywords.join(", "),
                :timestamp => file_data.timestamp,
                :album_id => target_album_id
            )
            @photo_data = file_data
            @photo
        end

        def delete(picasa)
            picasa.photo.delete(photo.album_id,photo.id)
            @photo = nil
            @photo_data = nil
        end

        def load_photos(picasa)
            Album.set[photo_data.album_id].load_photos(picasa) if photo_data
            Album.set[file_data.album_id].load_photos(picasa) if file_data
        end

        def to_fuse(transform_dir)
            target_album = Album.set[file_data.album_id]
            album_path = target_album.to_fuse[0]
            transform_path = "#{transform_dir}/#{album_path}"
            FileUtils.mkpath(transform_path)

            file_path = Config.__transform__(file) { |ext| "#{transform_path}/#{id}.#{ext}" }[:file_path]

            ext = File.extname(file_path)
            path = "/#{album_path}/#{id}#{ext}"
            xattr = {}
            file_data.each_pair{ |k,v| xattr["user.#{k}"] = v.to_s }
            [ file_path, path, {:xattr => xattr} ]
        end

        def to_s
            data = file_data || album_data 
            album = Album.set[data.album_id] if data
            "#{id} #{album}"
        end

        def inspect
            <<-INSPECT
            #{id},
  file=#{file},
  picasa_id= #{photo.album_id if photo}, #{photo.id if photo},
            #{file_data.inspect if file_data},
            #{photo_data.inspect if photo_data}
            INSPECT

        end
    end
end
