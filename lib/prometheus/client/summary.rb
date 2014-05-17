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
          transform(@values[label_set_for(labels)])
        end
      end

      # Returns all label sets with their values
      def values
        synchronize do
          @values.reduce({}) do |memo, (labels, value)|
            memo[labels] = transform(value)
            memo
          end
        end
      end

      private

      def default
        Quantile::Estimator.new
      end

      def transform(estimator)
        estimator.invariants.reduce({}) do |memo, invariant|
          memo[invariant.quantile] = estimator.query(invariant.quantile)
          memo
        end
      end
    end
  end
end
