# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require 'rconbot/version'

Gem::Specification.new do |spec|
  spec.name        = "rconbot"
  spec.version     = RconBot::VERSION
  spec.date        = Time.now.strftime('%Y-%m-%d')
  spec.authors     = ["Schubert Cardozo"]
  spec.email       = ["cardozoschubert@gmail.com"]
  spec.homepage    = "https://github.com/saturnine/rconbot"
  spec.summary     = %q{A bot that sits on your server, administrates a match, collects statistics, and records via HLTV}
  spec.description = %q{A bot that sits on your server, administrates a match, collects statistics, and records via HLTV}

  spec.rubyforge_project = "rconbot"

  spec.files          = Dir.glob("**/*.rb")
  #spec.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  #spec.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  spec.require_paths  = ["lib"]

  spec.add_runtime_dependency('redis', '>= 3.0.2')
  spec.add_runtime_dependency('json', '>= 1.6.6')
  spec.add_runtime_dependency('state_machine', '>= 1.2.0')
  spec.add_development_dependency('rake', '>= 10.0.3')
  spec.add_development_dependency('rspec', '>= 2.11.0')
  spec.add_development_dependency('mocha', '>= 0.12.7')
  spec.add_development_dependency('simplecov', '>= 0.7.1')
  spec.add_development_dependency('coveralls', '>= 0.6.7')

  spec.required_ruby_version = '>= 1.9.2'
end
