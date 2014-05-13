require 'thread'
require 'prometheus/client/registry'

module Prometheus::Client
  describe Registry do
    let(:registry) { Registry.new }

    describe '.new' do
      it 'returns a new registry instance' do
        expect(registry).to be_a(Registry)
      end
    end

    describe '#register' do
      it 'registers a new metric container and returns it' do
        metric = double(name: :test)

        expect(registry.register(metric)).to eql(metric)
      end

      it 'raises an exception if a metric name gets registered twice' do
        metric = double(name: :test)

        registry.register(metric)

        expect do
          registry.register(metric)
        end.to raise_exception Registry::AlreadyRegisteredError
      end

      it 'is thread safe' do
        mutex = Mutex.new
        containers = []

        def registry.exist?(*args)
          super.tap { sleep(0.01) }
        end

        5.times.map do
          Thread.new do
            result = begin
              registry.register(double(name: :test))
            rescue Registry::AlreadyRegisteredError
            end
            mutex.synchronize { containers << result }
          end
        end.each(&:join)

        expect(containers.compact).to have(1).entry
      end
    end

    describe '#counter' do
      it 'registers a new counter metric container and returns the counter' do
        metric = registry.counter(:test, 'test docstring')

        expect(metric).to be_a(Counter)
      end
    end

    describe '#gauge' do
      it 'registers a new gauge metric container and returns the gauge' do
        metric = registry.gauge(:test, 'test docstring')

        expect(metric).to be_a(Gauge)
      end
    end

    describe '#summary' do
      it 'registers a new summary metric container and returns the summary' do
        metric = registry.summary(:test, 'test docstring')

        expect(metric).to be_a(Summary)
      end
    end

    describe '#exist?' do
      it 'returns true if a metric name has been registered' do
        registry.register(double(name: :test))

        expect(registry.exist?(:test)).to eql(true)
      end

      it 'returns false if a metric name has not been registered yet' do
        expect(registry.exist?(:test)).to eql(false)
      end
    end

    describe '#get' do
      it 'returns a previously registered metric container' do
        registry.register(double(name: :test))

        expect(registry.get(:test)).to be
      end

      it 'returns nil if the metric has not been registered yet' do
        expect(registry.get(:test)).to eql(nil)
      end
    end
  end
end
