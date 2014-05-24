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

    shared_examples 'ok' do |headers, fmt|
      it "responds with 200 OK and Content-Type #{fmt::CONTENT_TYPE}" do
        registry.counter(:foo, 'foo counter').increment({}, 9)

        get '/metrics', nil, headers

        expect(last_response.status).to eql(200)
        expect(last_response.header['Content-Type']).to eql(fmt::CONTENT_TYPE)
        expect(last_response.body).to eql(fmt.marshal(registry))
      end
    end

    shared_examples 'not acceptable' do |headers|
      it 'responds with 406 Not Acceptable' do
        message = 'Supported media types: text/plain, application/json'

        get '/metrics', nil, headers

        expect(last_response.status).to eql(406)
        expect(last_response.header['Content-Type']).to eql('text/plain')
        expect(last_response.body).to eql(message)
      end
    end

    context 'when client does not send a Accept header' do
      include_examples 'ok', {}, json
    end

    context 'when client accpets any media type' do
      accept = '*/*'

      include_examples 'ok', { 'HTTP_ACCEPT' => accept }, json
    end

    context 'when client requests application/json' do
      accept = 'application/json'

      include_examples 'ok', { 'HTTP_ACCEPT' => accept }, json
    end

    context "when client requests '#{json::CONTENT_TYPE}'" do
      accept = json::CONTENT_TYPE

      include_examples 'ok', { 'HTTP_ACCEPT' => accept }, json
    end

    context 'when client requests text/plain' do
      accept = 'text/plain'

      include_examples 'ok', { 'HTTP_ACCEPT' => accept }, text
    end

    context "when client requests '#{text::CONTENT_TYPE}'" do
      accept = text::CONTENT_TYPE

      include_examples 'ok', { 'HTTP_ACCEPT' => accept }, text
    end

    context 'when client uses different white spaces in Accept header' do
      accept = 'text/plain;q=1.0  ; version=0.0.4'

      include_examples 'ok', { 'HTTP_ACCEPT' => accept }, text
    end

    context 'when client accepts multiple formats' do
      accept = "#{json::CONTENT_TYPE};q=0.5, #{text::CONTENT_TYPE};q=0.7"

      include_examples 'ok', { 'HTTP_ACCEPT' => accept }, text
    end

    context 'when client does not include quality attribute' do
      accept = "#{json::CONTENT_TYPE};q=0.5, #{text::CONTENT_TYPE}"

      include_examples 'ok', { 'HTTP_ACCEPT' => accept }, text
    end

    context 'when client accepts some unknown formats' do
      accept = "#{text::CONTENT_TYPE};q=0.3, proto/buf;q=0.7"

      include_examples 'ok', { 'HTTP_ACCEPT' => accept }, text
    end

    context 'when client accepts only unknown formats' do
      accept = 'fancy/woo;q=0.3, proto/buf;q=0.7'

      include_examples 'not acceptable', 'HTTP_ACCEPT' => accept
    end

    context 'when client accepts unknown formats and wildcard' do
      accept = 'fancy/woo;q=0.3, proto/buf;q=0.7, */*;q=0.1'

      include_examples 'ok', { 'HTTP_ACCEPT' => accept }, json
    end
  end
end
