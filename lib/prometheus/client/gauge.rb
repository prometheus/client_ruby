require 'prometheus/client/metric'

module Prometheus
  module Client
    class Gauge < Metric
      def type
        :gauge
      end
    end
  end
end
