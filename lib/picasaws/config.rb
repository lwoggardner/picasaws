require 'pathname'
require 'delegate'
require 'mime-types'
require 'picasaws/optional_gems'

module PicasaWS

    class Decorator < SimpleDelegator

        def method_missing(method,*args)
            result = begin
                         super
                     rescue NoMethodError
                         nil
                     end
            @depth == 0 ? result : Decorator.new(@depth - 1, result)
        end

        def initialize(depth=0,object)
            @depth = depth
            super(object)
        end
    end

    class Config

        class << self
            attr_accessor :sync_id

            def __album_data__(dir_path)
                @album_config.__config_data__(dir_path)
            end


            def __file_data__(file_path)
                types = MIME::Types.type_for(file_path).map { |m| m.content_type }
                matched_configs = @configs.select() { |c| types.any? { |t| c.content_type.match(t) } }
                matched_configs.inject({}) { |h,c|  h.merge!(c.__config_data__(file_path)) }
            end

            def __transform__(file_path,&block)
                content_type = MIME::Types.type_for(file_path).collect {|m| m.content_type}.find { |ct| @transforms.has_key?(ct) }
                if content_type
                    output_type = @transforms[content_type].content_type
                    output_path = nil
                    if block_given?
                        ext =  MIME::Types[output_type].first.extensions.last
                        output_path = yield ext
                        return { file_path: output_path } if File.exists?(output_path)
                    end

                    binary = @transforms[content_type].__config_data__(file_path)

                    if output_path
                        File.open(output_path,"w") { |f| f.write(binary) }
                        { file_path: output_path }
                    else
                        { content_type: content_type, binary: binary }
                    end
                else
                    { file_path: file_path }
                end
            end
        end

        @sync_id = "pws"

        def self.configure(&block)
            self.class_eval(&block)
        end

        # @yieldreturn [Hash] of album params
        #   - id: the unique id of this album (default dir.basename)
        #   - comment: a descriptive comment for this album (default empty)
        #   - timestamp: epoch timestamp for this album (default empty)
        def self.album(&block)
            @album_config = self.new(nil,&block)
        end

        # @yieldreturn [Hash] of album params
        #   - id: the unique id of this album (default dir.basename, nil to skip)
        #   - comment: a descriptive comment for this album (default empty)
        #   - timestamp: epoch timestamp for this album (default empty)
        def self.photo(*content_types,&block)
            content_types = [/image\//] if content_types.empty?
            @configs.push(*(content_types.collect { |ct| self.new(ct,&block) }))
        end

        def self.video(*content_types,&block)
            content_types = [ /video\// ] if content_types.empty?
            photo(*content_types,&block)
        end

        # @yieldreturn [String,Blob] content_type, binary_data
        # @yieldreturn [String|Pathname] pathname to transformed (or original) file
        def self.transform(*content_types,&block)
            raise "at lest one content_type must be supplied" if content_types.empty?
            config = self.new(content_types.first,&block) 
            content_types.each { |ct| @transforms[ct] = config }
        end

        # @!visibility private
        def initialize(content_type,&func)
            @content_type = content_type
            define_singleton_method(:__config_function__,func)
        end

        # defaults

        album {{ id: dir.basename, title: dir.basename }}
        @configs = []
        photo {{ id: file.basename, timestamp: file.mtime }}
        video {{ id: file.basename, timestamp: file.mtime }}
        @transforms = {}
        transform("image/jpeg","image/tiff") { rmagick_resize() }

        attr_reader :content_type

        # @!visibility private
        def __config_data__(file_path)
            @file_path = file_path
            @file = nil
            @mime_type = nil
            @xattr = nil
            @exif = nil
            @xmp = nil
            @ffmpeg = nil
            __config_function__
        end


        attr_reader :file_path

        def dir
            file
        end

        def file
            @file ||= Pathname.new(file_path)
        end

        def xattr
            @xattr ||= safe_xattr()
        end

        def exif
            @exif ||= safe_exif()
        end

        def xmp
            @xmp ||= safe_xmp()
        end

        def mime_type
            @mime_type ||= MIME::Types.type_for(file_path).first
        end

        def ffmpeg
            @ffmpeg ||= safe_ffmpeg()
        end

        def join(*args,sep)
            args.reject { |x| !x }.uniq.join(sep)
        end

        def rmagick_resize(max_size=2048)
            OptionalGems.require('RMagick','rmagick') unless defined?(Magick)

            image = Magick::Image.read(file_path)[0]
            image.resize_to_fit!(max_size)
            image.format="JPG"
            image.to_blob
        end

        private

        def safe_xattr()
            OptionalGems.require('ffi-xattr') unless defined?(::Xattr) 
            Xattr.new(file_path)
        end

        def safe_exif()
            OptionalGems.require('exifr') unless defined?(::EXIFR)

            case mime_type.content_type
            when "image/jpeg"
                EXIFR::JPEG.new(file_path)
            when "image/tiff"
                EXIFR::TIFF.new(file_path)
            else
                raise "unsupported mime_type #{mime_type.content_type} for exif"
            end
        end

        def safe_xmp()
            OptionalGems.require('xmp') unless defined?(::XMP)
            raise "unsupported mime_type #{mime_type.content_type} for xmp" unless mime_type.content_type == "image/jpeg"
            Decorator.new(1,::XMP.parse(exif))
        end

        def safe_ffmpeg(path)
            OptionalGems.require('streamio-ffmpeg') unless defined?(::FFMPEG)
            FFMPEG::Movie.new(file_path) 
        end
    end
end
