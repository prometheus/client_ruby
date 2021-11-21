# encoding: UTF-8

require 'prometheus/client/push'

describe Prometheus::Client::Push do
  let(:gateway) { 'http://localhost:9091' }
  let(:registry) { Prometheus::Client.registry }
  let(:push) { Prometheus::Client::Push.new(job: 'test-job', gateway: gateway, open_timeout: 5, read_timeout: 30) }

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

    it 'escapes non-URL characters' do
      push = Prometheus::Client::Push.new(job: '<bar job>')

      expected = '/metrics/job/%3Cbar%20job%3E'
      expect(push.path).to eql(expected)
    end
  end

  describe '#request' do
    let(:content_type) { Prometheus::Client::Formats::Text::CONTENT_TYPE }
    let(:data) { Prometheus::Client::Formats::Text.marshal(registry) }
    let(:uri) { URI.parse("#{gateway}/metrics/job/test-job") }

    it 'sends marshalled registry to the specified gateway' do
      request = double(:request)
      expect(request).to receive(:content_type=).with(content_type)
      expect(request).to receive(:body=).with(data)
      expect(Net::HTTP::Post).to receive(:new).with(uri).and_return(request)

      http = double(:http)
      expect(http).to receive(:use_ssl=).with(false)
      expect(http).to receive(:open_timeout=).with(5)
      expect(http).to receive(:read_timeout=).with(30)
      expect(http).to receive(:request).with(request)
      expect(Net::HTTP).to receive(:new).with('localhost', 9091).and_return(http)

      push.send(:request, Net::HTTP::Post, registry)
    end

    it 'deletes data from the registry' do
      request = double(:request)
      expect(request).to receive(:content_type=).with(content_type)
      expect(Net::HTTP::Delete).to receive(:new).with(uri).and_return(request)

      http = double(:http)
      expect(http).to receive(:use_ssl=).with(false)
      expect(http).to receive(:open_timeout=).with(5)
      expect(http).to receive(:read_timeout=).with(30)
      expect(http).to receive(:request).with(request)
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
        expect(http).to receive(:request).with(request)
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
        expect(http).to receive(:request).with(request)
        expect(Net::HTTP).to receive(:new).with('localhost', 9091).and_return(http)

        push.send(:request, Net::HTTP::Put, registry)
      end
    end
  end
end
