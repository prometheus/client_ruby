# encoding: UTF-8

require 'prometheus/client/metric'

module Prometheus
  module Client
    # A Gauge is a metric that exposes merely an instantaneous value or some
    # snapshot thereof.
    class Gauge < Metric
      def type
        :gauge
      end

      # Sets the value for the given label set
      def set(labels, value)
        unless value.is_a?(Numeric)
          raise ArgumentError, 'value must be a number'
        end

        @values[label_set_for(labels)] = value.to_f
      end

      # Increments Gauge value by 1 or adds the given value to the Gauge.
      # (The value can be negative, resulting in a decrease of the Gauge.)
      def increment(labels = {}, by = 1)
        synchronize do
          label_set = label_set_for(labels)
          @values[label_set] ||= 0
          @values[label_set] += by
        end
      end

      # Decrements Gauge value by 1 or subtracts the given value from the Gauge.
      # (The value can be negative, resulting in a increase of the Gauge.)
      def decrement(labels = {}, by = 1)
        label_set = label_set_for(labels)
        synchronize do
          @values[label_set] ||= 0
          @values[label_set] -= by
        end
      end
    end
  end
end
