# encoding: UTF-8

require 'json'
require 'rack/test'
require 'prometheus/client/rack/exporter'

describe Prometheus::Client::Rack::Exporter do
  include Rack::Test::Methods

  let(:json_content_type) do
    'application/json; schema="prometheus/telemetry"; version=0.0.2'
  end

  let(:registry) do
    Prometheus::Client::Registry.new
  end

  let(:app) do
    app = ->(_) { [200, { 'Content-Type' => 'text/html' }, ['OK']] }
    Prometheus::Client::Rack::Exporter.new(app, registry: registry)
  end

  context 'when requesting app endpoints' do
    it 'returns the app response' do
      get '/foo'

      expect(last_response).to be_ok
      expect(last_response.body).to eql('OK')
    end
  end

  context 'when requesting /metrics' do
    it 'returns a prometheus compatible json response' do
      registry.counter(:foo, 'foo counter').increment({}, 9)

      get '/metrics'

      expect(last_response).to be_ok
      expect(last_response.header['Content-Type']).to eql(json_content_type)
      expect(last_response.body).to eql([
        {
          baseLabels: { __name__: 'foo' },
          docstring: 'foo counter',
          metric: {
            type: 'counter',
            value: [
              { labels: {}, value: 9 },
            ],
          },
        },
      ].to_json,)
    end
  end
end
