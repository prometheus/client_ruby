require 'json'
require 'thread'

require 'prometheus/client/container'
require 'prometheus/client/counter'
require 'prometheus/client/summary'
require 'prometheus/client/gauge'

module Prometheus
  module Client
    # Registry
    #
    #
    class Registry
      class AlreadyRegisteredError < StandardError; end

      def initialize()
        @containers = {}
        @mutex = Mutex.new
      end

      def register(name, docstring, metric, base_labels = {})
        container = Container.new(name, docstring, metric, base_labels)

        @mutex.synchronize do
          if exist?(name)
            raise AlreadyRegisteredError, "#{name} has already been registered"
          else
            @containers[name] = container
          end
        end

        container
      end

      def counter(name, docstring, base_labels = {})
        register(name, docstring, Counter.new, base_labels).metric
      end

      def summary(name, docstring, base_labels = {})
        register(name, docstring, Summary.new, base_labels).metric
      end

      def gauge(name, docstring, base_labels = {})
        register(name, docstring, Gauge.new, base_labels).metric
      end

      def exist?(name)
        @containers.has_key?(name)
      end

      def get(name)
        @containers[name]
      end

      def to_json(*json)
        @containers.values.to_json(*json)
      end
    end
  end
end
