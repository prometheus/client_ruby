# encoding: UTF-8

require 'thread'

require 'prometheus/client/counter'
require 'prometheus/client/summary'
require 'prometheus/client/gauge'

module Prometheus
  module Client
    # Registry
    class Registry
      class AlreadyRegisteredError < StandardError; end

      def initialize
        @metrics = {}
        @mutex = Mutex.new
      end

      def register(metric)
        name = metric.name

        @mutex.synchronize do
          if exist?(name.to_sym)
            fail AlreadyRegisteredError, "#{name} has already been registered"
          else
            @metrics[name.to_sym] = metric
          end
        end

        metric
      end

      def counter(name, docstring, base_labels = {})
        register(Counter.new(name, docstring, base_labels))
      end

      def summary(name, docstring, base_labels = {})
        register(Summary.new(name, docstring, base_labels))
      end

      def gauge(name, docstring, base_labels = {})
        register(Gauge.new(name, docstring, base_labels))
      end

      def exist?(name)
        @metrics.key?(name)
      end

      def get(name)
        @metrics[name.to_sym]
      end

      def metrics
        @metrics.values
      end
    end
  end
end
