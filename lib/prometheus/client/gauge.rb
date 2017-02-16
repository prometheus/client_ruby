# encoding: UTF-8

require 'prometheus/client/metric'

module Prometheus
  module Client
    # A Gauge is a metric that exposes merely an instantaneous value or some
    # snapshot thereof.
    class Gauge < Metric
      def initialize(name, docstring, base_labels = {}, multiprocess_mode=:all)
        super(name, docstring, base_labels)
        if ValueClass.multiprocess and ![:min, :max, :livesum, :liveall, :all].include?(multiprocess_mode)
          raise ArgumentError, 'Invalid multiprocess mode: ' + multiprocess_mode
        end
        @multiprocess_mode = multiprocess_mode
      end

      def type
        :gauge
      end

      def default(labels)
        ValueClass.new(type, @name, @name, labels, @multiprocess_mode)
      end

      # Sets the value for the given label set
      def set(labels, value)
        @values[label_set_for(labels)].set(value)
      end
    end
  end
end
