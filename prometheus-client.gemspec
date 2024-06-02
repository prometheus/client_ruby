# -*- encoding: utf-8 -*-
$LOAD_PATH.push File.expand_path('../lib', __FILE__)
require 'prometheus/client/version'

Gem::Specification.new do |s|
  s.name              = 'prometheus-client'
  s.version           = Prometheus::Client::VERSION
  s.summary           = 'A suite of instrumentation metric primitives' \
                        'that can be exposed through a web services interface.'
  s.authors           = ['Ben Kochie', 'Chris Sinjakli', 'Daniel Magliola']
  s.email             = ['superq@gmail.com', 'chris@sinjakli.co.uk', 'dmagliola@crystalgears.com']
  s.homepage          = 'https://github.com/prometheus/client_ruby'
  s.license           = 'Apache-2.0'

  s.files             = %w(README.md LICENSE) + Dir.glob('{lib/**/*}')
  s.require_paths     = ['lib']

  s.add_dependency 'base64'
  s.add_dependency 'bigdecimal'

  s.add_development_dependency 'benchmark-ips'
  s.add_development_dependency 'concurrent-ruby'
  s.add_development_dependency 'timecop'
end
