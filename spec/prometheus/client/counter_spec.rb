# encoding: UTF-8

require 'prometheus/client/counter'
require 'examples/metric_example'

describe Prometheus::Client::Counter do
  let(:counter) { Prometheus::Client::Counter.new(:foo, 'foo description') }

  it_behaves_like Prometheus::Client::Metric do
    let(:type) { Float }
  end

  describe '#increment' do
    it 'increments the counter' do
      expect do
        counter.increment
      end.to change { counter.get }.by(1.0)
    end

    it 'increments the counter for a given label set' do
      expect do
        expect do
          counter.increment(test: 'label')
        end.to change { counter.get(test: 'label') }.by(1.0)
      end.to_not change { counter.get }
    end

    it 'increments the counter by a given value' do
      expect do
        counter.increment({}, 5)
      end.to change { counter.get }.by(5.0)
    end

    it 'raises an ArgumentError on negative increments' do
      expect do
        counter.increment({}, -1)
      end.to raise_error ArgumentError
    end

    it 'returns the new counter value' do
      expect(counter.increment).to eql(1.0)
    end

    it 'is thread safe' do
      expect do
        Array.new(10) do
          Thread.new do
            10.times { counter.increment }
          end
        end.each(&:join)
      end.to change { counter.get }.by(100.0)
    end
  end
end
