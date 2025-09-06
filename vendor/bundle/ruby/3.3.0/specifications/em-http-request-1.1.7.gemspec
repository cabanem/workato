# -*- encoding: utf-8 -*-
# stub: em-http-request 1.1.7 ruby lib

Gem::Specification.new do |s|
  s.name = "em-http-request".freeze
  s.version = "1.1.7".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Ilya Grigorik".freeze]
  s.date = "2020-08-31"
  s.description = "EventMachine based, async HTTP Request client".freeze
  s.email = ["ilya@igvita.com".freeze]
  s.homepage = "http://github.com/igrigorik/em-http-request".freeze
  s.licenses = ["MIT".freeze]
  s.rubygems_version = "3.0.3".freeze
  s.summary = "EventMachine based, async HTTP Request client".freeze

  s.installed_by_version = "3.5.22".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<addressable>.freeze, [">= 2.3.4".freeze])
  s.add_runtime_dependency(%q<cookiejar>.freeze, ["!= 0.3.1".freeze])
  s.add_runtime_dependency(%q<em-socksify>.freeze, [">= 0.3".freeze])
  s.add_runtime_dependency(%q<eventmachine>.freeze, [">= 1.0.3".freeze])
  s.add_runtime_dependency(%q<http_parser.rb>.freeze, [">= 0.6.0".freeze])
  s.add_development_dependency(%q<mongrel>.freeze, ["~> 1.2.0.pre2".freeze])
  s.add_development_dependency(%q<multi_json>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rack>.freeze, ["< 2.0".freeze])
  s.add_development_dependency(%q<rake>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rspec>.freeze, [">= 0".freeze])
end
