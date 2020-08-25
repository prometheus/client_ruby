# encoding: UTF-8

require 'thread'

require 'prometheus/client/counter'
require 'prometheus/client/summary'
require 'prometheus/client/gauge'
require 'prometheus/client/histogram'

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
          if @metrics.key?(name.to_sym)
            raise AlreadyRegisteredError, "#{name} has already been registered"
          end
          @metrics[name.to_sym] = metric
        end

        metric
      end

      def unregister(name)
        @mutex.synchronize do
          @metrics.delete(name.to_sym)
        end
      end

      def counter(name, docstring:, labels: [], preset_labels: {}, store_settings: {})
        register(Counter.new(name,
                             docstring: docstring,
                             labels: labels,
                             preset_labels: preset_labels,
                             store_settings: store_settings))
      end

      def summary(name, docstring:, labels: [], preset_labels: {}, store_settings: {})
        register(Summary.new(name,
                             docstring: docstring,
                             labels: labels,
                             preset_labels: preset_labels,
                             store_settings: store_settings))
      end

      def gauge(name, docstring:, labels: [], preset_labels: {}, store_settings: {})
        register(Gauge.new(name,
                           docstring: docstring,
                           labels: labels,
                           preset_labels: preset_labels,
                           store_settings: store_settings))
      end

      def histogram(name, docstring:, labels: [], preset_labels: {},
                    buckets: Histogram::DEFAULT_BUCKETS,
                    store_settings: {})
        register(Histogram.new(name,
                               docstring: docstring,
                               labels: labels,
                               preset_labels: preset_labels,
                               buckets: buckets,
                               store_settings: store_settings))
      end

      def exist?(name)
        @mutex.synchronize { @metrics.key?(name) }
      end

      def get(name)
        @mutex.synchronize { @metrics[name.to_sym] }
      end

      def metrics
        @mutex.synchronize { @metrics.values }
      end
    end
  end
end
