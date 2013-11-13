require 'quantile'
require 'prometheus/client/metric'

module Prometheus
  module Client
    class Summary < Metric
      def type
        :histogram
      end

      # Records a given value.
      def add(labels, value)
        label_set = label_set_for(labels)
        synchronize { @values[label_set].observe(value) }
      end

      # Returns the value for the given label set
      def get(labels = {})
        synchronize do
          estimator = @values[label_set_for(labels)]
          estimator.invariants.inject({}) do |memo, invariant|
            memo[invariant.quantile] = estimator.query(invariant.quantile)
            memo
          end
        end
      end

    private

      def default
        Quantile::Estimator.new
      end

    end
  end
end
