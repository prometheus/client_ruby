# encoding: UTF-8

require 'prometheus/client/metric'

module Prometheus
  module Client
    # Counter is a metric that exposes merely a sum or tally of things.
    class Counter < Metric
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

      private

      def default
        0
      end
    end
  end
end
