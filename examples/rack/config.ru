require 'rack'
require 'prometheus/client/rack/collector'
require 'prometheus/client/rack/exporter'

app = Rack::Builder.new do
  use Rack::Deflater, if: ->(_, _, _, body) { body.any? && body[0].length > 512 }
  use Prometheus::Client::Rack::Collector
  use Prometheus::Client::Rack::Exporter
end

Rack::Handler::WEBrick.run ->(_) { [200, { 'Content-Type' => 'text/html' }, ['OK']] }
