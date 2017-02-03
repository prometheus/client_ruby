# encoding: UTF-8

require 'prometheus/client/metric'
require 'prometheus/client/valuetype'

module Prometheus
  module Client
    # Counter is a metric that exposes merely a sum or tally of things.
    class Counter < Metric
      def type
        :counter
      end

      def increment(labels = {}, by = 1)
        raise ArgumentError, 'increment must be a non-negative number' if by < 0

        label_set = label_set_for(labels)
        synchronize { @values[label_set].increment(by) }
      end

      private

      def default(labels)
        ValueType.new(type, @name, @name, labels)
      end
    end
  end
end
