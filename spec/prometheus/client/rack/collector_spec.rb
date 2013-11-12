require_relative '../../../../lib/prometheus/client/rack/collector'
require 'rack/test'

describe Prometheus::Client::Rack::Collector do
  include Rack::Test::Methods

  let(:registry) do
    Prometheus::Client::Registry.new
  end

  let(:app) do
    app = lambda { |env| [200, {'Content-Type' => 'text/html'}, ['OK']] }
    Prometheus::Client::Rack::Collector.new(app, registry: registry)
  end

  it 'returns the app response' do
    get '/foo'

    expect(last_response).to be_ok
    expect(last_response.body).to eql('OK')
  end

  it 'handles errors in the registry gracefully' do
    app
    registry.get(:http_requests_total).metric.should_receive(:increment).and_raise(NoMethodError)

    get '/foo'

    expect(last_response).to be_ok
  end

  it 'traces request information' do
    Time.should_receive(:now).twice.and_return(0.0, 0.000042)
    expected_labels = { method: 'get', path: '/foo', code: '200' }

    get '/foo'

    expect(registry.to_json).to eql([
      {
        baseLabels: { name: 'http_requests_total' },
        docstring: 'A counter of the total number of HTTP requests made',
        metric: {
          type: 'counter',
          value: [{ labels: expected_labels, value: 1 }]
        }
      },
      {
        baseLabels: { name: 'http_request_durations_total_microseconds' },
        docstring: 'The total amount of time Rack has spent answering HTTP requests (microseconds).',
        metric: {
          type: 'counter',
          value: [{ labels: expected_labels, value: 42 }]
        }
      },
      {
        baseLabels: { name: 'http_request_durations_microseconds' },
        docstring: 'A histogram of the response latency for requests made (microseconds).',
        metric: {
          type: 'histogram',
          value: [{ labels: expected_labels, value: { '0.5' => 42, '0.9' => 42, '0.99' => 42 } }]
        }
      }
    ].to_json)
  end
end
