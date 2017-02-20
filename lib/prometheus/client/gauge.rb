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
    end
  end
end
