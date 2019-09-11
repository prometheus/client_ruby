# encoding: UTF-8

require 'thread'
require 'prometheus/client/registry'

describe Prometheus::Client::Registry do
  let(:registry) { Prometheus::Client::Registry.instance }

  describe '.new' do
    it 'returns a new registry instance' do
      expect(registry).to be_a(Prometheus::Client::Registry)
    end
  end

  describe '#register' do
    let(:registry) { Prometheus::Client::Registry.clone.instance }

    it 'registers a new metric container and returns it' do
      metric = double(name: :test)

      expect(registry.register(metric)).to eql(metric)
    end

    it 'returns a metric if a metric name tries to register twice' do
      metric = double(name: :test)

      registry.register(metric)

      expect(registry.metrics.size).to eq 1
    end

    it 'is thread safe' do
      def registry.exist?(*args)
        super.tap { sleep(0.01) }
      end

      Array.new(5) do
        Thread.new do
          registry.register(double(name: :test))
        end
      end.each(&:join)

      expect(registry.metrics.size).to eql(1)
    end
  end

  describe '#unregister' do
    it 'unregister a registered metric' do
      registry.register(double(name: :test))
      registry.unregister(:test)
      expect(registry.exist?(:test)).to eql(false)
    end

    it "doesn't raise when unregistering a not registered metrics" do
      expect do
        registry.unregister(:test)
      end.not_to raise_error
    end
  end

  describe '#counter' do
    it 'registers a new counter metric container and returns the counter' do
      metric = registry.counter(:test, docstring: 'test docstring')

      expect(metric).to be_a(Prometheus::Client::Counter)
    end
  end

  describe '#gauge' do
    it 'registers a new gauge metric container and returns the gauge' do
      metric = registry.gauge(:test, docstring: 'test docstring')

      expect(metric).to be_a(Prometheus::Client::Gauge)
    end
  end

  describe '#summary' do
    it 'registers a new summary metric container and returns the summary' do
      metric = registry.summary(:test, docstring: 'test docstring')

      expect(metric).to be_a(Prometheus::Client::Summary)
    end
  end

  describe '#histogram' do
    it 'registers a new histogram metric container and returns the histogram' do
      metric = registry.histogram(:test, docstring: 'test docstring')

      expect(metric).to be_a(Prometheus::Client::Histogram)
    end
  end

  describe '#exist?' do
    let(:registry) { Prometheus::Client::Registry.clone.instance }

    it 'returns true if a metric name has been registered' do
      registry.register(double(name: :test))

      expect(registry.exist?(:test)).to eql(true)
    end

    it 'returns false if a metric name has not been registered yet' do
      expect(registry.exist?(:test)).to eql(false)
    end
  end

  describe '#get' do
    let(:registry) { Prometheus::Client::Registry.clone.instance }

    it 'returns a previously registered metric container' do
      registry.register(double(name: :test))

      expect(registry.get(:test)).to be
    end

    it 'returns nil if the metric has not been registered yet' do
      expect(registry.get(:test)).to eql(nil)
    end
  end
end
