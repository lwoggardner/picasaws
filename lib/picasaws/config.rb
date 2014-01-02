require 'pathname'
require 'delegate'
require 'mime-types'
require 'picasaws/optional_gems'

module PicasaWS

    #@!visibility private
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

    # Configuration for PicasaWS
    #
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

        # Configuration block
        # 
        # @example
        #    # This is equivalent to the default configuration
        #    PicasaWS::Config.configure do
        #
        #       album {{ id: dir.basename, title: dir.basename }}
        #
        #       photo {{ id: file.basename, timestamp: file.mtime }}
        #
        #       video {{ id: ((file.size < 104857600) ? file.basename : nil), timestamp: file.mtime }}
        #
        #       transform("image/jpeg","image/tiff") { rmagick_resize() }
        #
        #    end
        def self.configure(&block)
            self.class_eval(&block)
        end

        # Set the configuration for albums
        #
        # Map information about {#dir} to album id and metadata
        #
        # @yieldreturn [Hash] of album configuration params
        #   - id: the unique id of this album (default {#dir}.basename, nil to skip)
        #   - comment: a descriptive comment for this album (default empty)
        #   - timestamp: epoch timestamp for this album (default dir.mtime}
        def self.album(&block)
            @album_config = self.new(nil,&block)
        end

        # Add a configuration for files
        # 
        # Map information about {#file} to image id and metadata
        #
        # The configurations are applied to files in the order in which they are
        # defined. If the content type matches the block is called and its results
        # merged into any previous results (ie last config wins)
        #
        # @param [Array<String|Regex>] content_types
        #    list of mime content types to apply this configuration to
        #    if none are supplied the regex /image\// is used
        #
        # @yieldreturn [Hash] of photo params
        #   - id: the *unique* id of this photo 
        #   - timestamp: epoch timestamp for this album 
        #   - caption: a descriptive comment for this album 
        #   - keywords: comma separated list of tags or keywords (default empty)
        #
        # @example
        #   # default mapping to match /image\//
        #   photo {{ id: file.basename, timestamp: file.mtime }}
        def self.photo(*content_types,&block)
            content_types = [/image\//] if content_types.empty?
            @configs.push(*(content_types.collect { |ct| self.new(ct,&block) }))
        end

        # Convenience method to add cofiguration for files with content type
        # matching /video\//
        #
        # See {.photo} 
        # @example
        #   # default mapping to match /video\//
        #   # skip files > 100Mb (not permitted by Picasa)
        #   video {{ id: ((file.size < 104857600) ? file.basename : nil), timestamp: file.mtime }}
        def self.video(*content_types,&block)
            content_types = [ /video\// ] if content_types.empty?
            photo(*content_types,&block)
        end

        # Add a transform configuration for one or more content types
        #
        # The block will operate on {#file} and transform it in some way
        #
        # @param [Array<String>] content_types
        #    one or more exact content type strings that this transform applies to
        #    the first entry is the output content-type
        #
        # @yieldreturn [String] binary data representing the transformed image
        #    must be of the content-type specified by first entry in content_types
        #
        # @example
        #   # this transform is added by default
        #   transform("image/jpeg","image/tiff") { rmagick_resize() }
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

        @configs = []
        @transforms = {}
        album {{ id: dir.basename, title: dir.basename }}
        photo {{ id: file.basename, timestamp: file.mtime }}
        video {{ id: ((file.size < 104857600) ? file.basename : nil), timestamp: file.mtime }}
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

        # @return [Pathname] the path being configured
        #    for albums this will be a directory, for photos/videos a file
        def file
            @file ||= Pathname.new(file_path)
        end
        alias :dir :file

        # See {http://rubydoc.info/gems/ffi-xattr/Xattr ffi-xattr} gem
        #
        # @return [Xattr] the extended attributes for {#file}
        def xattr
            @xattr ||= safe_xattr()
        end

        # See {http://rubydoc.info/gems/exifr exifr} gem
        #
        # Applies to content type "image/jpeg" or "image/tiff" only
        # @return [EXIFR::JPEG|EXIFR::TIFF] exif information about {#file}
        def exif
            @exif ||= safe_exif()
        end

        # See {http://rubydoc.info/gems/xmp/XMP xmp} gem
        #
        # Applies to content type "image/jpeg" only
        # @return [XMP] a proxy for the XMP information about {#file}
        #     XMP would normally raise exceptions when referencing tags that do not occur in the file
        #     where this object will return nil
        def xmp
            @xmp ||= safe_xmp()
        end

        # @return [MIME::Type] the mime type for {#file}
        def mime_type
            @mime_type ||= MIME::Types.type_for(file_path).first
        end

        # Applies to video content only
        # #TODO UNTESTED!!!
        # @return [FFMPEG::Movie] video information for {#file}
        def ffmpeg
            @ffmpeg ||= safe_ffmpeg()
        end

        # Utility method to join an array of values with a separator, ignoring nils.
        # @return [String]
        def join(*args,sep)
            args.reject { |x| !x }.uniq.join(sep)
        end

        # Transform method applies to "image/jpeg" or "image/tiff" only
        # @param [Integer] max_size 
        # @return [Blob] the transformed image data (always a jpeg)
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
