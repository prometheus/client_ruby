require 'prometheus/client/metric'

module Prometheus
  module Client
    class Counter < Metric
      def default
        0
      end

      def type
        :counter
      end

      def increment(labels = {}, by = 1)
        label_set = label_set_for(labels)
        synchronize { @values[label_set] += by }
      end

      def decrement(labels = {}, by = 1)
        increment(labels, -by)
      end
    end
  end
end
