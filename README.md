# PicasaWS - Picasa Web Sync

Keep Picasaweb albums synchronised with a local directory of photos and videos

## Installation

    gem install picasaws

And then execute:

    $ picasaws


## Configuration

Some configuration is required to map album and photo metadata from your files
to picasa. The default configuration just uses filenames and timestamps, and implements a transform to keep images within picasa's free storage size limits

See the examples

* etc/exif.conf.rb - obtain title and keyword information from exif and xmp
* etc/shotwell.conf.rb - obtains information from extended attributes provided by 
    {http://rubygems.org/gems/shotwellfs shotwellfs}

and the detailled documentation for {PicasaWS::Config}

Configuration is passed to the commands using --config

## Commands

### show

    $ picasaws show

List albums and image information as they will appear in picasa. Useful to test your configuration.

### fuse

    $ picasaws fuse

Starts a FUSE virtual filesystem that lists images in a flattened album structure as it
will appear in picasa. Metadata that will be available to picasa is available in extended attributes.

### sync

    $ picasaws sync

Uploads your albums to picasa, synchronises metadata, and deletes an albums no longer in your filesystem.  Only albums that were originally uploaded by picasaws are touched.

TODO authentication

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
