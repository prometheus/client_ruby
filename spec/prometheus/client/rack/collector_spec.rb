require 'rack/test'
require 'prometheus/client/rack/collector'

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
    registry.get(:http_requests_total).should_receive(:increment).and_raise(NoMethodError)

    get '/foo'

    expect(last_response).to be_ok
  end

  it 'traces request information' do
    Time.should_receive(:now).twice.and_return(0.0, 0.000002)
    expected_labels = { method: 'get', path: '/foo', code: '200' }

    get '/foo'

    {
      http_requests_total: 1,
      http_request_durations_total_microseconds: 2,
      http_request_durations_microseconds: { 0.5 => 2, 0.9 => 2, 0.99 => 2 },
    }.each do |metric, result|
      expect(registry.get(metric).get(expected_labels)).to eql(result)
    end
  end
end
