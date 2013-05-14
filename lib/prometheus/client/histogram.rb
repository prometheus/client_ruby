require 'prometheus/client/metric'

module Prometheus
  module Client
    class Histogram < Metric
      def type
        :histogram
      end

      def add(labels, timing)
        raise NotImplementedError
      end

      def measure(labels, &block)
        raise NotImplementedError
      end
    end
  end
end
