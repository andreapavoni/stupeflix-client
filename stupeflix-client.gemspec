# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'stupeflix/version'

Gem::Specification.new do |spec|
  spec.name          = "stupeflix-client"
  spec.version       = Stupeflix::VERSION
  spec.authors       = ["Andrea Pavoni"]
  spec.email         = ["andrea.pavoni@gmail.com"]
  spec.description   = %q{A Ruby client for http://stupeflix.com API}
  spec.summary       = %q{A Ruby client for http://stupeflix.com API}
  spec.homepage      = "https://github.com/apeacox/stupeflix-client"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
end
