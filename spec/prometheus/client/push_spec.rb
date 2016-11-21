# encoding: UTF-8

require 'prometheus/client/push'

describe Prometheus::Client::Push do
  let(:registry) { Prometheus::Client.registry }
  let(:push) { Prometheus::Client::Push.new('test-job') }

  describe '.new' do
    it 'returns a new push instance' do
      expect(push).to be_a(Prometheus::Client::Push)
    end

    it 'uses localhost as default Pushgateway' do
      expect(push.gateway).to eql('http://localhost:9091')
    end

    it 'allows to specify a custom Pushgateway' do
      push = Prometheus::Client::Push.new('test-job', nil, 'http://pu.sh:1234')

      expect(push.gateway).to eql('http://pu.sh:1234')
    end

    it 'raises an ArgumentError if the given gateway URL is invalid' do
      ['inva.lid:1233', 'http://[invalid]'].each do |url|
        expect do
          Prometheus::Client::Push.new('test-job', nil, url)
        end.to raise_error ArgumentError
      end
    end
  end

  describe '#path' do
    it 'uses the default metrics path if no instance value given' do
      push = Prometheus::Client::Push.new('test-job')

      expect(push.path).to eql('/metrics/jobs/test-job')
    end

    it 'uses the full metrics path if an instance value is given' do
      push = Prometheus::Client::Push.new('bar-job', 'foo')

      expect(push.path).to eql('/metrics/jobs/bar-job/instances/foo')
    end

    it 'escapes non-URL characters' do
      push = Prometheus::Client::Push.new('bar job', 'foo <my instance>')

      expected = '/metrics/jobs/bar%20job/instances/foo%20%3Cmy%20instance%3E'
      expect(push.path).to eql(expected)
    end
  end

  describe '#add' do
    it 'pushes a given registry to the configured Pushgateway via HTTP' do
      http = double(:http)
      expect(http).to receive(:send_request).with(
        'POST',
        '/metrics/jobs/foo/instances/bar',
        Prometheus::Client::Formats::Text.marshal(registry),
        'Content-Type' => Prometheus::Client::Formats::Text::CONTENT_TYPE,
      )
      expect(http).to receive(:use_ssl=).with(false)
      expect(Net::HTTP).to receive(:new).with('pu.sh', 9091).and_return(http)

      described_class.new('foo', 'bar', 'http://pu.sh:9091').add(registry)
    end

    it 'pushes a given registry to the configured Pushgateway via HTTPS' do
      http = double(:http)
      expect(http).to receive(:send_request).with(
        'POST',
        '/metrics/jobs/foo/instances/bar',
        Prometheus::Client::Formats::Text.marshal(registry),
        'Content-Type' => Prometheus::Client::Formats::Text::CONTENT_TYPE,
      )
      expect(http).to receive(:use_ssl=).with(true)
      expect(Net::HTTP).to receive(:new).with('pu.sh', 9091).and_return(http)

      described_class.new('foo', 'bar', 'https://pu.sh:9091').add(registry)
    end
  end

  describe '#replace' do
    it 'replaces any existing metrics with registry' do
      http = double(:http)
      expect(http).to receive(:send_request).with(
        'PUT',
        '/metrics/jobs/foo/instances/bar',
        Prometheus::Client::Formats::Text.marshal(registry),
        'Content-Type' => Prometheus::Client::Formats::Text::CONTENT_TYPE,
      )
      expect(http).to receive(:use_ssl=).with(false)
      expect(Net::HTTP).to receive(:new).with('pu.sh', 9091).and_return(http)

      described_class.new('foo', 'bar', 'http://pu.sh:9091').replace(registry)
    end
  end

  describe '#delete' do
    it 'deletes existing metrics from the configured Pushgateway' do
      http = double(:http)
      expect(http).to receive(:send_request).with(
        'DELETE',
        '/metrics/jobs/foo/instances/bar',
      )
      expect(http).to receive(:use_ssl=).with(false)
      expect(Net::HTTP).to receive(:new).with('pu.sh', 9091).and_return(http)

      described_class.new('foo', 'bar', 'http://pu.sh:9091').delete
    end
  end
end
