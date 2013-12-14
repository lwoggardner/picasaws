# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'picasaws/version'

Gem::Specification.new do |gem|
  gem.name          = "picasaws"
  gem.version       = PicasaWS::VERSION
  gem.authors       = ["lwoggardner"]
  gem.email         = ["grant@lastweekend.com.au"]
  gem.description   = %q{Picasa Web Sync}
  gem.summary       = %q{Sync filesystem to Picasa Web}
  gem.homepage      = "https://github.com/lwoggardner/picasaws"

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_dependency("picasa")
  gem.add_dependency("thor")
  gem.add_dependency("mime-types")
  gem.add_development_dependency("rmagick")
  gem.add_development_dependency("exifr")
  gem.add_development_dependency("xmp")
  gem.add_development_dependency("rfusefs")
  gem.add_development_dependency("ffi-xattr")
  
end
