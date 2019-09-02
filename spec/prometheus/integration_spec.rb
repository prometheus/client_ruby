# encoding: UTF-8

require 'rack/test'
require 'rack'
require 'prometheus/middleware/collector'
require 'prometheus/middleware/exporter'

API = Rack::Builder.new do
  use Rack::Deflater
  use Prometheus::Middleware::Collector
  use Prometheus::Middleware::Exporter

  map "/" do
    run ->(_) { [200, {'Content-Type' => 'text/html'}, ['OK']] }
  end
end

describe API do
  include Rack::Test::Methods

  let(:app) { described_class }

  context 'GET /metrics' do
    it 'fails on the second request' do
      get '/metrics'
      expect { last_response }.not_to raise_error
      expect { get '/metrics' }.not_to raise_error
    end
  end
end

