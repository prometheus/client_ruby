# encoding: UTF-8

require 'rack/test'
require 'prometheus/middleware/collector'

describe Prometheus::Middleware::Collector do
  include Rack::Test::Methods

  let(:registry) do
    Prometheus::Client::Registry.new
  end

  let(:original_app) do
    ->(_) { [200, { 'Content-Type' => 'text/html' }, ['OK']] }
  end

  let!(:app) do
    described_class.new(original_app, registry: registry)
  end

  it 'returns the app response' do
    get '/foo'

    expect(last_response).to be_ok
    expect(last_response.body).to eql('OK')
  end

  it 'handles errors in the registry gracefully' do
    counter = registry.get(:http_server_requests_total)
    expect(counter).to receive(:increment).and_raise(NoMethodError)

    get '/foo'

    expect(last_response).to be_ok
  end

  it 'traces request information' do
    expect(Time).to receive(:now).twice.and_return(0.0, 0.2)

    get '/foo'

    metric = :http_server_requests_total
    labels = { method: 'get', path: '/foo', code: '200' }
    expect(registry.get(metric).get(labels)).to eql(1.0)

    metric = :http_server_request_duration_seconds
    labels = { method: 'get', path: '/foo' }
    expect(registry.get(metric).get(labels)).to include(0.1 => 0, 0.25 => 1)
  end

  context 'when the app raises an exception' do
    let(:original_app) do
      lambda do |env|
        raise NoMethodError if env['PATH_INFO'] == '/broken'

        [200, { 'Content-Type' => 'text/html' }, ['OK']]
      end
    end

    before do
      get '/foo'
    end

    it 'traces exceptions' do
      expect { get '/broken' }.to raise_error NoMethodError

      metric = :http_server_exceptions_total
      labels = { exception: 'NoMethodError' }
      expect(registry.get(metric).get(labels)).to eql(1.0)
    end
  end

  context 'when using a custom counter label builder' do
    let(:app) do
      described_class.new(
        original_app,
        registry: registry,
        counter_label_builder: lambda do |env, code|
          {
            code:   code,
            method: env['REQUEST_METHOD'].downcase,
          }
        end,
      )
    end

    it 'allows labels configuration' do
      get '/foo/bar'

      metric = :http_server_requests_total
      labels = { method: 'get', code: '200' }
      expect(registry.get(metric).get(labels)).to eql(1.0)
    end
  end
end
