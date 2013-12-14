require 'picasa'
require 'picasaws/config'

module PicasaWS
    class Album

        AlbumData = Struct.new(:title, :timestamp, :comment) do
            def self.create(from_hash)
                args = members.collect() { |m| from_hash[m] }
                self.new(*args)
            end
        end

        attr_reader :id, :dir,:album, :dir_data, :album_data

        def self.set
            @albums ||= Hash.new() { |h,k| h[k] = Album.new(k)}
        end

        def self.from_directory(dir)
            values = Config.__album_data__(dir)
            values[:timestamp] = values[:timestamp].to_i if values[:timestamp]           
            values[:title] = values[:title].to_s 
            values[:comment] = values[:comment].to_s 
            id = values[:id]
            if id
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
        end

        def set_dir(dir,data)
            @dir = dir
            @dir_data = data
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
                [:delete,"Deleting album #{id}"]
            when album.nil?
                [:create,"Creating album #{id}"]
            when !dir_data.eql?(album_data)
                [:sync, "Synching album data #{id}\n - dir #{dir_data}\n - web #{album_data}"]
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
            @album
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
    end

    class Image
        attr_reader :id, :album_id, :file, :file_data, :photo, :photo_data

        ImageData = Struct.new(:album_id, :timestamp, :caption, :keywords) do
            def self.create(hash)
                args = members.collect() { |m| hash[m] }
                self.new(*args)
            end
        end

        def self.set
            @images ||= Hash.new() { |h,k| h[k] = Image.new(k)}
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
        end

        def set_file(file,data)
            @file = file
            @file_data = data
        end

        def set_photo(photo,data)
            @photo = photo
            @photo_data = data
        end

        def action
            case
            when file.nil? && (photo.nil? || Album.set[photo_data.album_id].action == :ignore_deleted)
                [:ignore_deleted, nil]
                unless photo.nil?
                    @photo = nil
                    @photo_data = nil
                end
            when file.nil?
                [:delete, "Deleting image #{id} from #{ALbum.set[photo_data.album_id].album_data.title}"]
            when photo.nil? && !Album.set[file_data.album_id].album
                [:wait_album_create, nil]
            when photo.nil?
                [:create, "Creating image #{id} in #{Album.set[file_data.album_id].album_data.title}"]
            when !file_data.eql?(photo_data)
                [:sync, "Synchronising image #{id}\n - file #{file_data}\n - web  #{photo_data}"]
            else
                [:ignore_synced,nil]
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
            puts "#{file_path} #{path}"
            [ file_path, path, {:xattr => xattr} ]
        end
    end
end
