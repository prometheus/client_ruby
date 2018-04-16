require 'rack'
require 'prometheus/middleware/collector'
require 'prometheus/middleware/exporter'

use Rack::Deflater
use Prometheus::Middleware::Collector
use Prometheus::Middleware::Exporter

srand

app = lambda do |_|
  case rand
  when 0..0.8
    [200, { 'Content-Type' => 'text/html' }, ['OK']]
  when 0.8..0.95
    [404, { 'Content-Type' => 'text/html' }, ['Not Found']]
  else
    raise NoMethodError, 'It is a bug!'
  end
end

run app
