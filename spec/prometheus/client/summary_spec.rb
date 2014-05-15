# encoding: UTF-8

require 'prometheus/client/summary'
require 'examples/metric_example'

describe Prometheus::Client::Summary do
  let(:summary) { Prometheus::Client::Summary.new(:bar, 'bar description') }

  it_behaves_like Prometheus::Client::Metric do
    let(:type) { Hash }
  end

  describe '#type' do
    it 'returns histogram for API compatibility' do
      expect(summary.type).to eql(:histogram)
    end
  end

  describe '#add' do
    it 'records the given value' do
      expect do
        summary.add({}, 5)
      end.to change { summary.get }
    end
  end

  describe '#get' do
    it 'returns a set of quantile values' do
      summary.add({ foo: 'bar' }, 3)
      summary.add({ foo: 'bar' }, 5.2)
      summary.add({ foo: 'bar' }, 13)
      summary.add({ foo: 'bar' }, 4)

      expect(summary.get(foo: 'bar')).to eql(0.5 => 4, 0.9 => 5.2, 0.99 => 5.2)
    end

    it 'uses nil as default value' do
      expect(summary.get({})).to eql(0.5 => nil, 0.9 => nil, 0.99 => nil)
    end
  end

end
