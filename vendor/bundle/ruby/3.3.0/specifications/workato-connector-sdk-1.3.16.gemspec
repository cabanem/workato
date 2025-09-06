# -*- encoding: utf-8 -*-
# stub: workato-connector-sdk 1.3.16 ruby lib

Gem::Specification.new do |s|
  s.name = "workato-connector-sdk".freeze
  s.version = "1.3.16".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://support.workato.com/", "documentation_uri" => "https://docs.workato.com/developing-connectors/sdk/cli.html", "homepage_uri" => "https://www.workato.com/", "rubygems_mfa_required" => "true", "source_code_uri" => "https://github.com/workato/workato-connector-sdk" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Pavel Abolmasov".freeze]
  s.bindir = "exe".freeze
  s.date = "2025-08-18"
  s.description = "Reproduce key concepts of Workato SDK, DSL, behavior and constraints.".freeze
  s.email = ["pavel.abolmasov@workato.com".freeze]
  s.executables = ["workato".freeze]
  s.files = ["exe/workato".freeze]
  s.homepage = "https://www.workato.com/".freeze
  s.licenses = ["MIT".freeze]
  s.post_install_message = "\nIf you updated from workato-connector-sdk prior 1.2.0 your tests could be broken.\n\nFor more details see here:\nhttps://github.com/workato/workato-connector-sdk/releases/tag/v1.2.0\n\n".freeze
  s.required_ruby_version = Gem::Requirement.new(">= 2.7.6".freeze)
  s.rubygems_version = "3.1.6".freeze
  s.summary = "Gem for running adapter's code outside Workato infrastructure".freeze

  s.installed_by_version = "3.5.22".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<activesupport>.freeze, [">= 5.2".freeze, "< 7.1".freeze])
  s.add_runtime_dependency(%q<aws-sigv4>.freeze, ["~> 1.2".freeze, ">= 1.2.4".freeze])
  s.add_runtime_dependency(%q<bundler>.freeze, ["~> 2.0".freeze])
  s.add_runtime_dependency(%q<charlock_holmes>.freeze, ["~> 0.7".freeze, ">= 0.7.7".freeze])
  s.add_runtime_dependency(%q<concurrent-ruby>.freeze, ["~> 1.0".freeze, "!= 1.3.5".freeze])
  s.add_runtime_dependency(%q<em-http-request>.freeze, ["~> 1.0".freeze])
  s.add_runtime_dependency(%q<gyoku>.freeze, ["~> 1.3".freeze, ">= 1.3.1".freeze])
  s.add_runtime_dependency(%q<i18n>.freeze, [">= 0.9.5".freeze, "< 2.0".freeze])
  s.add_runtime_dependency(%q<jwt>.freeze, [">= 1.5.6".freeze, "< 3.0".freeze])
  s.add_runtime_dependency(%q<launchy>.freeze, ["~> 2.0".freeze])
  s.add_runtime_dependency(%q<net-http-digest_auth>.freeze, ["~> 1.4".freeze])
  s.add_runtime_dependency(%q<nokogiri>.freeze, [">= 1.13.10".freeze, "< 1.19".freeze])
  s.add_runtime_dependency(%q<public_suffix>.freeze, [">= 4.0.7".freeze, "< 6.0".freeze])
  s.add_runtime_dependency(%q<rack>.freeze, ["~> 2.0".freeze])
  s.add_runtime_dependency(%q<rails-html-sanitizer>.freeze, ["~> 1.4".freeze, ">= 1.4.3".freeze])
  s.add_runtime_dependency(%q<rest-client>.freeze, ["= 2.1.0".freeze])
  s.add_runtime_dependency(%q<ruby-progressbar>.freeze, ["~> 1.0".freeze])
  s.add_runtime_dependency(%q<ruby_rncryptor>.freeze, ["~> 3.0".freeze])
  s.add_runtime_dependency(%q<rubyzip>.freeze, ["~> 2.3".freeze])
  s.add_runtime_dependency(%q<sorbet-runtime>.freeze, ["~> 0.5".freeze])
  s.add_runtime_dependency(%q<thor>.freeze, ["~> 1.0".freeze])
  s.add_runtime_dependency(%q<webrick>.freeze, ["~> 1.0".freeze])
end
