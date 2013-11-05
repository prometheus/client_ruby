Gem::Specification.new do |s|
  s.name              = 'prometheus-client'
  s.version           = '0.1.0'
  s.summary           = 'A suite of instrumentation metric primitives for Ruby that can be exposed through a JSON web services interface.'
  s.author            = 'Tobias Schmidt'
  s.email             = 'grobie@soundcloud.com'
  s.homepage          = 'http://github.com/prometheus/client_ruby'

  s.files             = %w(README.md) + Dir.glob('{lib/**/*}')
  s.require_paths     = ['lib']
end
