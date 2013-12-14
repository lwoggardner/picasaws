module PicasaWS

    module OptionalGems
        def self.require(gem,install_name=gem)
            begin
                Kernel.require "#{gem}"
            rescue LoadError
                Kernel.require 'rubygems/dependency_installer' unless defined?(Gem::DependencyInstaller)
                Gem::DependencyInstaller.new().install(install_name)
                Kernel.require "#{gem}"
            end
        end
    end
end
