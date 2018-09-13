# encoding: UTF-8

require 'prometheus/client/metric'

module Prometheus
  module Client
    # Summary is an accumulator for samples. It captures Numeric data and
    # provides the total count and sum of observations.
    class Summary < Metric
      # Value represents the state of a Summary at a given point.
      class Value
        attr_accessor :sum, :total

        def initialize
          @sum = 0.0
          @total = 0.0
        end

        def observe(value)
          @sum += value
          @total += 1
        end
      end

      def type
        :summary
      end

      # Records a given value.
      def observe(value, labels: {})
        label_set = label_set_for(labels)
        synchronize { @values[label_set].observe(value) }
      end

      private

      def reserved_labels
        [:quantile]
      end

      def default
        Value.new
      end
    end
  end
end
