# encoding: UTF-8

require 'json'
require 'rack/test'
require 'prometheus/client/rack/exporter'

describe Prometheus::Client::Rack::Exporter do
  include Rack::Test::Methods

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
    text = Prometheus::Client::Formats::Text
    json = Prometheus::Client::Formats::JSON

    shared_examples 'response' do |headers, format|
      it 'returns a valid prometheus compatible response' do
        registry.counter(:foo, 'foo counter').increment({}, 9)

        get '/metrics', nil, headers

        expect(last_response).to be_ok
        expect(last_response.header['Content-Type']).to eql(format::TYPE)
        expect(last_response.body).to eql(format.marshal(registry))
      end
    end

    context 'when client does send a Accept header' do
      include_examples 'response', {}, json
    end

    context 'when client requests application/json' do
      headers = { 'HTTP_ACCEPT' => json::TYPE }

      include_examples 'response', headers, json
    end

    context 'when client requests text/plain' do
      headers = { 'HTTP_ACCEPT' => text::TYPE }

      include_examples 'response', headers, text
    end

    context 'when client uses different white spaces in Accept header' do
      headers = { 'HTTP_ACCEPT' => 'text/plain;q=1.0  ; version=0.0.4' }

      include_examples 'response', headers, text
    end

    context 'when client accepts multiple formats' do
      headers = { 'HTTP_ACCEPT' => "#{json::TYPE};q=0.5, #{text::TYPE};q=0.7" }

      include_examples 'response', headers, text
    end

    context 'when client does not include quality attribute' do
      headers = { 'HTTP_ACCEPT' => "#{json::TYPE};q=0.5, #{text::TYPE}" }

      include_examples 'response', headers, text
    end

    context 'when client accepts some unknown formats' do
      headers = { 'HTTP_ACCEPT' => "#{text::TYPE};q=0.3, proto/buf;q=0.7" }

      include_examples 'response', headers, text
    end

    context 'when client accepts only unknown formats' do
      headers = { 'HTTP_ACCEPT' => 'fancy/woo;q=0.3, proto/buf;q=0.7' }

      include_examples 'response', headers, json
    end
  end
end
