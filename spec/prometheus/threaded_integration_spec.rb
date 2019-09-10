# encoding: UTF-8

require 'rack/test'
require 'rack'
require 'prometheus/middleware/collector'
require 'prometheus/middleware/exporter'
require "concurrent"

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
    it "fails when it's multi threaded request" do
      latch = Concurrent::CountDownLatch.new(1)

      t1 = Thread.new do
        latch.wait
        res = get '/metrics'

        expect(res.body).not_to be_empty
      end

      t2 = Thread.new do
        latch.wait
        res = get '/metrics'

        expect(res.body).not_to be_empty
      end

      t3 = Thread.new do
        latch.wait
        res = get '/metrics'
        expect(res.body).not_to be_empty
      end

      t4 = Thread.new do
        latch.wait
        res = get '/metrics'
        expect(res.body).not_to be_empty
      end

      latch.count_down

      [t1, t2, t3, t4].each(&:join)
    end
  end
end
