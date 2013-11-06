require 'prometheus/client/metric'

module Prometheus
  module Client
    class Gauge < Metric
      def type
        :gauge
      end

      # Sets the value for the given label set
      def set(labels, value)
        @values[label_set_for(labels)] = value
      end
    end
  end
end
