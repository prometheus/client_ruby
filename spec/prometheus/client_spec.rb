# encoding: UTF-8

require 'prometheus/client'

describe Prometheus::Client do
  describe '.registry' do
    it 'returns a registry object' do
      expect(Prometheus::Client.registry).to be_a(Prometheus::Client::Registry)
    end

    it 'memorizes the returned object' do
      expect(Prometheus::Client.registry).to eql(Prometheus::Client.registry)
    end
  end
end
