# -*- encoding: utf-8 -*-
# stub: em-socksify 0.3.3 ruby lib

Gem::Specification.new do |s|
  s.name = "em-socksify".freeze
  s.version = "0.3.3".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Ilya Grigorik".freeze]
  s.date = "2024-07-18"
  s.description = "Transparent proxy support for any EventMachine protocol".freeze
  s.email = ["ilya@igvita.com".freeze]
  s.homepage = "https://github.com/igrigorik/em-socksify".freeze
  s.licenses = ["MIT".freeze]
  s.rubygems_version = "3.3.26".freeze
  s.summary = "Transparent proxy support for any EventMachine protocol".freeze

  s.installed_by_version = "3.5.22".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<base64>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<eventmachine>.freeze, [">= 1.0.0.beta.4".freeze])
  s.add_development_dependency(%q<rspec>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rake>.freeze, [">= 0".freeze])
end
