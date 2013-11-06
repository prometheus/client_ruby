require 'thread'
require 'prometheus/client/registry'

module Prometheus::Client
  describe Registry do
    let(:registry) { Registry.new }

    describe '.new' do
      it 'returns a new registry instance' do
        registry.should be_a(Registry)
      end
    end

    describe '#register' do
      it 'registers a new metric container and returns it' do
        container = registry.register(:test, 'test docstring', double)

        registry.get(:test).should eql(container)
      end

      it 'raises an exception if a reserved base label is used' do
        expect do
          registry.register(:test, 'test docstring', double, { :name => 'reserved' })
        end.to raise_exception
      end

      it 'raises an exception if a metric name gets registered twice' do
        registry.register(:test, 'test docstring', double)

        expect do
          registry.register(:test, 'test docstring', double)
        end.to raise_exception
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
              registry.register(:test, 'test docstring', double)
            rescue Registry::AlreadyRegisteredError
            end
            mutex.synchronize { containers << result }
          end
        end.each(&:join)

        containers.compact.should have(1).entry
      end
    end

    describe '#counter' do
      it 'registers a new counter metric container and returns the counter' do
        metric = registry.counter(:test, 'test docstring')

        metric.should be_a(Counter)
      end
    end

    describe '#gauge' do
      it 'registers a new gauge metric container and returns the gauge' do
        metric = registry.gauge(:test, 'test docstring')

        metric.should be_a(Gauge)
      end
    end

    describe '#summary' do
      it 'registers a new summary metric container and returns the summary' do
        metric = registry.summary(:test, 'test docstring')

        metric.should be_a(Summary)
      end
    end

    describe '#exist?' do
      it 'returns true if a metric name has been registered' do
        registry.register(:test, 'test docstring', double)

        registry.exist?(:test).should eql(true)
      end

      it 'returns false if a metric name has not been registered yet' do
        registry.exist?(:test).should eql(false)
      end
    end

    describe '#get' do
      it 'returns a previously registered metric container' do
        registry.register(:test, 'test docstring', double)

        registry.get(:test).should be
      end

      it 'returns nil if the metric has not been registered yet' do
        registry.get(:test).should eql(nil)
      end
    end
  end
end
