# encoding: UTF-8

require 'prometheus/client/metric'

module Prometheus
  module Client
    # A histogram samples observations (usually things like request durations
    # or response sizes) and counts them in configurable buckets. It also
    # provides a sum of all observed values.
    class Histogram < Metric
      # DEFAULT_BUCKETS are the default Histogram buckets. The default buckets
      # are tailored to broadly measure the response time (in seconds) of a
      # network service. (From DefBuckets client_golang)
      DEFAULT_BUCKETS = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1,
                         2.5, 5, 10].freeze

      attr_reader :buckets

      # Offer a way to manually specify buckets
      def initialize(name,
                     docstring:,
                     labels: [],
                     preset_labels: {},
                     buckets: DEFAULT_BUCKETS,
                     store_settings: {})
        raise ArgumentError, 'Unsorted buckets, typo?' unless sorted?(buckets)

        @buckets = buckets
        super(name,
              docstring: docstring,
              labels: labels,
              preset_labels: preset_labels,
              store_settings: store_settings)
      end

      def type
        :histogram
      end

      def observe(value, labels: {})
        base_label_set = label_set_for(labels)

        @store.synchronize do
          buckets.each do |upper_limit|
            next if value > upper_limit
            @store.increment(labels: base_label_set.merge(le: upper_limit), by: 1)
          end
          @store.increment(labels: base_label_set.merge(le: "+Inf"), by: 1)
          @store.increment(labels: base_label_set.merge(le: "sum"), by: value)
        end
      end

      # Returns a hash with all the buckets plus +Inf (count) plus Sum for the given label set
      def get(labels: {})
        base_label_set = label_set_for(labels)

        all_buckets = buckets + ["+Inf", "sum"]

        @store.synchronize do
          all_buckets.each_with_object({}) do |upper_limit, acc|
            acc[upper_limit.to_s] = @store.get(labels: base_label_set.merge(le: upper_limit))
          end.tap do |acc|
            acc["count"] = acc["+Inf"]
          end
        end
      end

      # Returns all label sets with their values expressed as hashes with their buckets
      def values
        v = @store.all_values

        v.each_with_object({}) do |(label_set, v), acc|
          actual_label_set = label_set.reject{|l| l == :le }
          acc[actual_label_set] ||= @buckets.map{|b| [b.to_s, 0.0]}.to_h
          acc[actual_label_set][label_set[:le].to_s] = v
        end
      end

      private

      def reserved_labels
        [:le]
      end

      def sorted?(bucket)
        bucket.each_cons(2).all? { |i, j| i <= j }
      end
    end
  end
end
