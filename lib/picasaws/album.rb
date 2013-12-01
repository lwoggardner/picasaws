require 'ffi-xattr'
require 'picasa'

module PicasaWS
    class Album

        XATTR_ALBUMID="user.picasa.albumid"
        XATTR_DESC="user.picasa.summary"

        AlbumData = Struct.new("AlbumData",:title,:comment)

        attr_reader :id, :dir,:album, :dir_data, :album_data

        def self.set
            @albums ||= Hash.new() { |h,k| h[k] = Album.new(k)}
        end

        def self.find_directory(dir)
            xattr = Xattr.new(dir)
            title = File.basename(dir)
            id = xattr[XATTR_ALBUMID] || title
            comment = xattr[XATTR_DESC] || ""
            self.set[id].set_dir(dir,AlbumData.new(title,comment))
            self.set[id]
        end

        def self.find_album(web_album)
            summary = web_album.summary
            parsed =  summary.match(/\(rps:(.+)\)/)
            if parsed
                id = parsed[1]
                title   = web_album.title
                comment = parsed.pre_match
                self.set[id].set_album(web_album,AlbumData.new(title,comment))
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
            "#{dir_data.comment} (rps:#{id})"
        end

        def create(picasa)
            @album = picasa.album.create(
                :title => dir_data.title,
                :summary => comment_to_summary,
                :access => "private"
            )
            @album_data = dir_data
            @album
        end

        def sync(picasa)
            @album = picasa.album.update(
                album.id,
                :title => dir_data.title,
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
    end

    class Image
        attr_reader :id, :album_id, :file, :file_data, :photo, :photo_data

        ImageData = Struct.new("ImageData",:album_id, :timestamp, :comment,:keywords)

        XATTR_CAPTION="user.caption"
        XATTR_KEYWORDS="user.keywords"

        def self.set
            @images ||= Hash.new() { |h,k| h[k] = Image.new(k)}
        end

        def self.find_file(album_id, path)
            xattr = Xattr.new(path)
            id = File.basename(path,".*")
            timestamp = File.mtime(path).to_i
            comment = xattr[XATTR_CAPTION] || ""
            keywords = parse_keywords(xattr[XATTR_KEYWORDS])
            self.set[id].set_file(path,ImageData.new(album_id,timestamp,comment,keywords))
            self.set[id]
        end

        def self.find_photo(album_id, photo)
            id = photo.title
            timestamp = photo.timestamp.to_i
            comment = photo.summary
            keywords = parse_keywords(photo.media.keywords)
            self.set[id].set_photo(photo,ImageData.new(album_id,timestamp,comment,keywords))
            self.set[id]
        end

        def self.parse_keywords(str)
            return "" unless str
            str.split(/, */).sort
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
                [:create, "Creating image #{id} in #{Album.set[file_Data.album_id].album_data.title}"]
            when !file_data.eql?(photo_data)
                [:sync, "Synchronising image #{id}\n - file #{file_data}\n - web  #{photo_data}"]
            else
                [:ignore_synced,nil]
            end
        end

        def create(picasa)
            @photo = picasa.photo.create(
                Album.set[file_data.album_id].album.id,
                :file_path => file,
                :title => id,
                :summary => file_data.comment,
                :keywords => file_data.keywords,
                :timestamp => file_data.timestamp
            )
            @photo_data = file_data
            @photo
        end

        def sync(picasa)
            target_album_id = Album.set[file_data.album_id].album.id

            @photo = picasa.photo.update(
                photo.album_id,photo.id,
                :title => id,
                :summary => file_data.comment,
                :keywords => file_data.keywords,
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
    end
end
