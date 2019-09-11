# encoding: UTF-8

require 'prometheus/client/counter'
require 'prometheus/client/summary'
require 'prometheus/client/gauge'
require 'prometheus/client/histogram'
require 'concurrent'
require 'singleton'

module Prometheus
  module Client
    # Registry
    class Registry
      class AlreadyRegisteredError < StandardError; end

      include Singleton

      def initialize
        @metrics = {}
        @lock    = Concurrent::ReentrantReadWriteLock.new
      end

      def register(metric)
        name = metric.name

        @lock.with_write_lock do
          return metric if exist?(name.to_sym)

          @metrics[name.to_sym] = metric
        end

        metric
      end

      def unregister(name)
        @lock.with_write_lock do
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
        @lock.with_read_lock do
          @metrics.key?(name)
        end
      end

      def get(name)
        @lock.with_read_lock do
          @metrics[name.to_sym]
        end
      end

      def metrics
        @lock.with_read_lock do
          @metrics.values
        end
      end
    end
  end
end
