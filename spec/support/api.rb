require 'rack'

API = Rack::Builder.new do
  use Rack::Deflater
  use Prometheus::Middleware::Collector
  use Prometheus::Middleware::Exporter

  map "/" do
    run ->(_) { [200, {'Content-Type' => 'text/html'}, ['OK']] }
  end
end


