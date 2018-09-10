# encoding: UTF-8

require 'prometheus/client/gauge'
require 'examples/metric_example'

describe Prometheus::Client::Gauge do
  let(:gauge) { Prometheus::Client::Gauge.new(:foo, docstring: 'foo description') }

  it_behaves_like Prometheus::Client::Metric do
    let(:type) { NilClass }
  end

  describe '#set' do
    it 'sets a metric value' do
      expect do
        gauge.set(42)
      end.to change { gauge.get }.from(nil).to(42)
    end

    it 'sets a metric value for a given label set' do
      expect do
        expect do
          gauge.set(42, labels: { test: 'value' })
        end.to change { gauge.get(labels: { test: 'value' }) }.from(nil).to(42)
      end.to_not change { gauge.get }
    end

    context 'given an invalid value' do
      it 'raises an ArgumentError' do
        expect do
          gauge.set(nil)
        end.to raise_exception(ArgumentError)
      end
    end
  end

  describe '#increment' do
    before do
      gauge.set(0, labels: RSpec.current_example.metadata[:labels] || {})
    end

    it 'increments the gauge' do
      expect do
        gauge.increment
      end.to change { gauge.get }.by(1.0)
    end

    it 'increments the gauge for a given label set', labels: { test: 'one' } do
      expect do
        expect do
          gauge.increment(labels: { test: 'one' })
        end.to change { gauge.get(labels: { test: 'one' }) }.by(1.0)
      end.to_not change { gauge.get(labels: { test: 'another' }) }
    end

    it 'increments the gauge by a given value' do
      expect do
        gauge.increment(by: 5)
      end.to change { gauge.get }.by(5.0)
    end

    it 'returns the new gauge value' do
      expect(gauge.increment).to eql(1.0)
    end

    it 'is thread safe' do
      expect do
        Array.new(10) do
          Thread.new do
            10.times { gauge.increment }
          end
        end.each(&:join)
      end.to change { gauge.get }.by(100.0)
    end
  end

  describe '#decrement' do
    before do
      gauge.set(0, labels: RSpec.current_example.metadata[:labels] || {})
    end

    it 'increments the gauge' do
      expect do
        gauge.decrement
      end.to change { gauge.get }.by(-1.0)
    end

    it 'decrements the gauge for a given label set', labels: { test: 'one' } do
      expect do
        expect do
          gauge.decrement(labels: { test: 'one' })
        end.to change { gauge.get(labels: { test: 'one' }) }.by(-1.0)
      end.to_not change { gauge.get(labels: { test: 'another' }) }
    end

    it 'decrements the gauge by a given value' do
      expect do
        gauge.decrement(by: 5)
      end.to change { gauge.get }.by(-5.0)
    end

    it 'returns the new gauge value' do
      expect(gauge.decrement).to eql(-1.0)
    end

    it 'is thread safe' do
      expect do
        Array.new(10) do
          Thread.new do
            10.times { gauge.decrement }
          end
        end.each(&:join)
      end.to change { gauge.get }.by(-100.0)
    end
  end
end
