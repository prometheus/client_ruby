# encoding: UTF-8

require 'prometheus/client/gauge'
require 'prometheus/client/push'

describe Prometheus::Client::Push do
  let(:gateway) { 'http://localhost:9091' }
  let(:registry) { Prometheus::Client::Registry.new }
  let(:grouping_key) { {} }
  let(:push) { Prometheus::Client::Push.new(job: 'test-job', gateway: gateway, grouping_key: grouping_key, open_timeout: 5, read_timeout: 30) }

  describe '.new' do
    it 'returns a new push instance' do
      expect(push).to be_a(Prometheus::Client::Push)
    end

    it 'uses localhost as default Pushgateway' do
      push = Prometheus::Client::Push.new(job: 'test-job')

      expect(push.gateway).to eql('http://localhost:9091')
    end

    it 'allows to specify a custom Pushgateway' do
      push = Prometheus::Client::Push.new(job: 'test-job', gateway: 'http://pu.sh:1234')

      expect(push.gateway).to eql('http://pu.sh:1234')
    end

    it 'raises an ArgumentError if the job is nil' do
      expect do
        Prometheus::Client::Push.new(job: nil)
      end.to raise_error ArgumentError
    end

    it 'raises an ArgumentError if the job is empty' do
      expect do
        Prometheus::Client::Push.new(job: "")
      end.to raise_error ArgumentError
    end

    it 'raises an ArgumentError if the given gateway URL is invalid' do
      ['inva.lid:1233', 'http://[invalid]'].each do |url|
        expect do
          Prometheus::Client::Push.new(job: 'test-job', gateway: url)
        end.to raise_error ArgumentError
      end
    end

    it 'raises InvalidLabelError if a grouping key label has an invalid name' do
      expect do
        Prometheus::Client::Push.new(job: "test-job", grouping_key: { "not_a_symbol" => "foo" })
      end.to raise_error Prometheus::Client::LabelSetValidator::InvalidLabelError
    end
  end

  describe '#add' do
    it 'sends a given registry to via HTTP POST' do
      expect(push).to receive(:request).with(Net::HTTP::Post, registry)

      push.add(registry)
    end
  end

  describe '#replace' do
    it 'sends a given registry to via HTTP PUT' do
      expect(push).to receive(:request).with(Net::HTTP::Put, registry)

      push.replace(registry)
    end
  end

  describe '#delete' do
    it 'deletes existing metrics with HTTP DELETE' do
      expect(push).to receive(:request).with(Net::HTTP::Delete)

      push.delete
    end
  end

  describe '#path' do
    it 'uses the default metrics path if no grouping key given' do
      push = Prometheus::Client::Push.new(job: 'test-job')

      expect(push.path).to eql('/metrics/job/test-job')
    end

    it 'appends additional grouping labels to the path if specified' do
      push = Prometheus::Client::Push.new(
        job: 'test-job',
        grouping_key: { foo: "bar", baz: "qux"},
      )

      expect(push.path).to eql('/metrics/job/test-job/foo/bar/baz/qux')
    end

    it 'encodes grouping key label values containing `/` in url-safe base64' do
      push = Prometheus::Client::Push.new(
        job: 'test-job',
        grouping_key: { foo: "bar/baz"},
      )

      expect(push.path).to eql('/metrics/job/test-job/foo@base64/YmFyL2Jheg==')
    end

    it 'encodes empty grouping key label values as a single base64 padding character' do
      push = Prometheus::Client::Push.new(
        job: 'test-job',
        grouping_key: { foo: ""},
      )

      expect(push.path).to eql('/metrics/job/test-job/foo@base64/=')
    end

    it 'escapes non-URL characters' do
      push = Prometheus::Client::Push.new(job: '<bar job>', grouping_key: { foo_label: '<bar value>' })

      expected = '/metrics/job/%3Cbar%20job%3E/foo_label/%3Cbar%20value%3E'
      expect(push.path).to eql(expected)
    end
  end

  describe '#request' do
    let(:content_type) { Prometheus::Client::Formats::Text::CONTENT_TYPE }
    let(:data) { Prometheus::Client::Formats::Text.marshal(registry) }
    let(:uri) { URI.parse("#{gateway}/metrics/job/test-job") }
    let(:response) do
      double(
        :response,
        code: '200',
        message: 'OK',
        body: 'Everything worked'
      )
    end

    it 'sends marshalled registry to the specified gateway' do
      request = double(:request)
      expect(request).to receive(:content_type=).with(content_type)
      expect(request).to receive(:body=).with(data)
      expect(Net::HTTP::Post).to receive(:new).with(uri).and_return(request)

      http = double(:http)
      expect(http).to receive(:use_ssl=).with(false)
      expect(http).to receive(:open_timeout=).with(5)
      expect(http).to receive(:read_timeout=).with(30)
      expect(http).to receive(:request).with(request).and_return(response)
      expect(Net::HTTP).to receive(:new).with('localhost', 9091).and_return(http)

      push.send(:request, Net::HTTP::Post, registry)
    end

    context 'for a 3xx response' do
      let(:response) do
        double(
          :response,
          code: '301',
          message: 'Moved Permanently',
          body: 'Probably no body, but technically you can return one'
        )
      end

      it 'raises a redirect error' do
        request = double(:request)
        allow(request).to receive(:content_type=)
        allow(request).to receive(:body=)
        allow(Net::HTTP::Post).to receive(:new).with(uri).and_return(request)

        http = double(:http)
        allow(http).to receive(:use_ssl=)
        allow(http).to receive(:open_timeout=)
        allow(http).to receive(:read_timeout=)
        allow(http).to receive(:request).with(request).and_return(response)
        allow(Net::HTTP).to receive(:new).with('localhost', 9091).and_return(http)

        expect { push.send(:request, Net::HTTP::Post, registry) }.to raise_error(
          Prometheus::Client::Push::HttpRedirectError
        )
      end
    end

    context 'for a 4xx response' do
      let(:response) do
        double(
          :response,
          code: '400',
          message: 'Bad Request',
          body: 'Info on why the request was bad'
        )
      end

      it 'raises a client error' do
        request = double(:request)
        allow(request).to receive(:content_type=)
        allow(request).to receive(:body=)
        allow(Net::HTTP::Post).to receive(:new).with(uri).and_return(request)

        http = double(:http)
        allow(http).to receive(:use_ssl=)
        allow(http).to receive(:open_timeout=)
        allow(http).to receive(:read_timeout=)
        allow(http).to receive(:request).with(request).and_return(response)
        allow(Net::HTTP).to receive(:new).with('localhost', 9091).and_return(http)

        expect { push.send(:request, Net::HTTP::Post, registry) }.to raise_error(
          Prometheus::Client::Push::HttpClientError
        )
      end
    end

    context 'for a 5xx response' do
      let(:response) do
        double(
          :response,
          code: '500',
          message: 'Internal Server Error',
          body: 'Apology for the server code being broken'
        )
      end

      it 'raises a server error' do
        request = double(:request)
        allow(request).to receive(:content_type=)
        allow(request).to receive(:body=)
        allow(Net::HTTP::Post).to receive(:new).with(uri).and_return(request)

        http = double(:http)
        allow(http).to receive(:use_ssl=)
        allow(http).to receive(:open_timeout=)
        allow(http).to receive(:read_timeout=)
        allow(http).to receive(:request).with(request).and_return(response)
        allow(Net::HTTP).to receive(:new).with('localhost', 9091).and_return(http)

        expect { push.send(:request, Net::HTTP::Post, registry) }.to raise_error(
          Prometheus::Client::Push::HttpServerError
        )
      end
    end

    it 'deletes data from the registry' do
      request = double(:request)
      expect(request).to receive(:content_type=).with(content_type)
      expect(Net::HTTP::Delete).to receive(:new).with(uri).and_return(request)

      http = double(:http)
      expect(http).to receive(:use_ssl=).with(false)
      expect(http).to receive(:open_timeout=).with(5)
      expect(http).to receive(:read_timeout=).with(30)
      expect(http).to receive(:request).with(request).and_return(response)
      expect(Net::HTTP).to receive(:new).with('localhost', 9091).and_return(http)

      push.send(:request, Net::HTTP::Delete)
    end

    context 'HTTPS support' do
      let(:gateway) { 'https://localhost:9091' }

      it 'uses HTTPS when requested' do
        request = double(:request)
        expect(request).to receive(:content_type=).with(content_type)
        expect(request).to receive(:body=).with(data)
        expect(Net::HTTP::Post).to receive(:new).with(uri).and_return(request)

        http = double(:http)
        expect(http).to receive(:use_ssl=).with(true)
        expect(http).to receive(:open_timeout=).with(5)
        expect(http).to receive(:read_timeout=).with(30)
        expect(http).to receive(:request).with(request).and_return(response)
        expect(Net::HTTP).to receive(:new).with('localhost', 9091).and_return(http)

        push.send(:request, Net::HTTP::Post, registry)
      end
    end

    context 'Basic Auth support' do
      let(:gateway) { 'https://super:secret@localhost:9091' }

      it 'sets Basic Auth header when requested' do
        request = double(:request)
        expect(request).to receive(:content_type=).with(content_type)
        expect(request).to receive(:basic_auth).with('super', 'secret')
        expect(request).to receive(:body=).with(data)
        expect(Net::HTTP::Put).to receive(:new).with(uri).and_return(request)

        http = double(:http)
        expect(http).to receive(:use_ssl=).with(true)
        expect(http).to receive(:open_timeout=).with(5)
        expect(http).to receive(:read_timeout=).with(30)
        expect(http).to receive(:request).with(request).and_return(response)
        expect(Net::HTTP).to receive(:new).with('localhost', 9091).and_return(http)

        push.send(:request, Net::HTTP::Put, registry)
      end
    end

    context 'with a grouping key that clashes with a metric label' do
      let(:grouping_key) { { foo: "bar"} }

      before do
        gauge = Prometheus::Client::Gauge.new(
          :test_gauge,
          labels: [:foo],
          docstring: "test docstring"
        )
        registry.register(gauge)
        gauge.set(42, labels: { foo: "bar" })
      end

      it 'raises an error when grouping key labels conflict with metric labels' do
        expect { push.send(:request, Net::HTTP::Post, registry) }.to raise_error(
          Prometheus::Client::LabelSetValidator::InvalidLabelSetError
        )
      end
    end
  end
end
