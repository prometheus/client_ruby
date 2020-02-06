# encoding: UTF-8

require 'rack/test'
require 'prometheus/middleware/collector'

describe Prometheus::Middleware::Collector do
  include Rack::Test::Methods

  # Reset the data store
  before do
    Prometheus::Client.config.data_store = Prometheus::Client::DataStores::Synchronized.new
  end

  let(:registry) do
    Prometheus::Client::Registry.new
  end

  let(:original_app) do
    ->(_) { [200, { 'Content-Type' => 'text/html' }, ['OK']] }
  end

  let!(:app) do
    described_class.new(original_app, registry: registry)
  end

  let(:dummy_error) { RuntimeError.new("Dummy error from tests") }

  it 'returns the app response' do
    get '/foo'

    expect(last_response).to be_ok
    expect(last_response.body).to eql('OK')
  end

  it 'handles errors in the registry gracefully' do
    counter = registry.get(:http_server_requests_total)
    expect(counter).to receive(:increment).and_raise(dummy_error)

    get '/foo'

    expect(last_response).to be_ok
  end

  it 'traces request information' do
    expect(Benchmark).to receive(:realtime).and_yield.and_return(0.2)

    get '/foo'

    metric = :http_server_requests_total
    labels = { method: 'get', path: '/foo', code: '200' }
    expect(registry.get(metric).get(labels: labels)).to eql(1.0)

    metric = :http_server_request_duration_seconds
    labels = { method: 'get', path: '/foo' }
    expect(registry.get(metric).get(labels: labels)).to include("0.1" => 0, "0.25" => 1)
  end

  it 'normalizes paths containing numeric IDs by default' do
    expect(Benchmark).to receive(:realtime).and_yield.and_return(0.3)

    get '/foo/42/bars'

    metric = :http_server_requests_total
    labels = { method: 'get', path: '/foo/:id/bars', code: '200' }
    expect(registry.get(metric).get(labels: labels)).to eql(1.0)

    metric = :http_server_request_duration_seconds
    labels = { method: 'get', path: '/foo/:id/bars' }
    expect(registry.get(metric).get(labels: labels)).to include("0.1" => 0, "0.5" => 1)
  end

  it 'normalizes paths containing UUIDs by default' do
    expect(Benchmark).to receive(:realtime).and_yield.and_return(0.3)

    get '/foo/5180349d-a491-4d73-af30-4194a46bdff3/bars'

    metric = :http_server_requests_total
    labels = { method: 'get', path: '/foo/:uuid/bars', code: '200' }
    expect(registry.get(metric).get(labels: labels)).to eql(1.0)

    metric = :http_server_request_duration_seconds
    labels = { method: 'get', path: '/foo/:uuid/bars' }
    expect(registry.get(metric).get(labels: labels)).to include("0.1" => 0, "0.5" => 1)
  end

  context 'when the app raises an exception' do
    let(:original_app) do
      lambda do |env|
        raise dummy_error if env['PATH_INFO'] == '/broken'

        [200, { 'Content-Type' => 'text/html' }, ['OK']]
      end
    end

    before do
      get '/foo'
    end

    it 'traces exceptions' do
      expect { get '/broken' }.to raise_error RuntimeError

      metric = :http_server_exceptions_total
      labels = { exception: 'RuntimeError' }
      expect(registry.get(metric).get(labels: labels)).to eql(1.0)
    end
  end

  context 'when provided a custom metrics_prefix' do
    let!(:app) do
      described_class.new(
        original_app,
        registry: registry,
        metrics_prefix: 'lolrus',
      )
    end

    it 'provides alternate metric names' do
      expect(
        registry.get(:lolrus_requests_total),
      ).to be_a(Prometheus::Client::Counter)
      expect(
        registry.get(:lolrus_request_duration_seconds),
      ).to be_a(Prometheus::Client::Histogram)
      expect(
        registry.get(:lolrus_exceptions_total),
      ).to be_a(Prometheus::Client::Counter)
    end

    it "doesn't register the default metrics" do
      expect(registry.get(:http_server_requests_total)).to be(nil)
      expect(registry.get(:http_server_request_duration_seconds)).to be(nil)
      expect(registry.get(:http_server_exceptions_total)).to be(nil)
    end
  end

  context 'when provided custom labels' do
    let!(:app) do
      custom_labels = {env: "valid_env"}
      described_class.new(
        original_app,
        registry: registry,
        labels: custom_labels,
      )
    end

    it 'can find metrics with custom labels' do
      get '/foo'
      metric = :http_server_request_duration_seconds
      correct_labels = { method: 'get', path: '/foo', env: 'valid_env'}
      expect(registry.get(metric).get(labels: correct_labels)).to include("0.1" => 1, "0.25" => 1.0)

      incorrect_labels = { method: 'get', path: '/foo', env: 'invalid_env'}
      expect(registry.get(metric).get(labels: incorrect_labels)).to include("0.1" => 0, "0.25" => 0.0)
    end

  end
end
