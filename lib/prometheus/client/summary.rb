# encoding: UTF-8

require 'quantile'
require 'prometheus/client/metric'

module Prometheus
  module Client
    # Summary is an accumulator for samples. It captures Numeric data and
    # provides an efficient quantile calculation mechanism.
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
          estimator.invariants.reduce({}) do |memo, invariant|
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
