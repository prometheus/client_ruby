# encoding: UTF-8

require 'prometheus/client/metric'

module Prometheus
  module Client
    # Counter is a metric that exposes merely a sum or tally of things.
    class Counter < Metric
      def type
        :counter
      end

      def increment(by: 1, labels: {})
        raise ArgumentError, 'increment must be a non-negative number' if by < 0

        label_set = label_set_for(labels)
        @store.increment(labels: label_set, by: by)
      end
    end
  end
end
