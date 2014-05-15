# encoding: UTF-8

require 'prometheus/client/counter'
require 'examples/metric_example'

describe Prometheus::Client::Counter do
  let(:counter) { Prometheus::Client::Counter.new(:foo, 'foo description') }

  it_behaves_like Prometheus::Client::Metric do
    let(:type) { Fixnum }
  end

  describe '#increment' do
    it 'increments the counter' do
      expect do
        counter.increment
      end.to change { counter.get }.by(1)
    end

    it 'increments the counter for a given label set' do
      expect do
        expect do
          counter.increment(test: 'label')
        end.to change { counter.get(test: 'label') }.by(1)
      end.to_not change { counter.get }
    end

    it 'increments the counter by a given value' do
      expect do
        counter.increment({}, 5)
      end.to change { counter.get }.by(5)
    end

    it 'returns the new counter value' do
      expect(counter.increment).to eql(1)
    end

    it 'is thread safe' do
      expect do
        10.times.map do
          Thread.new do
            10.times { counter.increment }
          end
        end.each(&:join)
      end.to change { counter.get }.by(100)
    end
  end

  describe '#decrement' do
    it 'decrements the counter' do
      expect do
        counter.decrement
      end.to change { counter.get }.by(-1)
    end

    it 'decrements the counter for a given label set' do
      expect do
        expect do
          counter.decrement(test: 'label')
        end.to change { counter.get(test: 'label') }.by(-1)
      end.to_not change { counter.get }
    end

    it 'decrements the counter by a given value' do
      expect do
        counter.decrement({}, 5)
      end.to change { counter.get }.by(-5)
    end

    it 'is thread safe' do
      100.times { counter.increment }

      expect do
        10.times.map do
          Thread.new do
            10.times { counter.decrement }
          end
        end.each(&:join)
      end.to change { counter.get }.to(0)
    end
  end
end
