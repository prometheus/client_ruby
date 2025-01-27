# encoding: UTF-8

require 'prometheus/client/metric'

module Prometheus
  module Client
    # A histogram samples observations (usually things like request durations
    # or response sizes) and counts them in configurable buckets. It also
    # provides a total count and sum of all observed values.
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

      def self.linear_buckets(start:, width:, count:)
        count.times.map { |idx| start.to_f + idx * width }
      end

      def self.exponential_buckets(start:, factor: 2, count:)
        count.times.map { |idx| start.to_f * factor ** idx }
      end

      def with_labels(labels)
        new_metric = self.class.new(name,
                                    docstring: docstring,
                                    labels: @labels,
                                    preset_labels: preset_labels.merge(labels),
                                    buckets: @buckets,
                                    store_settings: @store_settings)

        # The new metric needs to use the same store as the "main" declared one, otherwise
        # any observations on that copy with the pre-set labels won't actually be exported.
        new_metric.replace_internal_store(@store)

        new_metric
      end

      def type
        :histogram
      end

      # Records a given value. The recorded value is usually positive
      # or zero. A negative value is accepted but prevents current
      # versions of Prometheus from properly detecting counter resets
      # in the sum of observations. See
      # https://prometheus.io/docs/practices/histograms/#count-and-sum-of-observations
      # for details.
      def observe(value, labels: {})
        bucket = buckets.bsearch { |upper_limit| upper_limit >= value  }
        bucket = "+Inf" if bucket.nil?

        base_label_set = label_set_for(labels)

        # This is basically faster than doing `.merge`
        bucket_label_set = base_label_set.dup
        bucket_label_set[:le] = bucket.to_s
        sum_label_set = base_label_set.dup
        sum_label_set[:le] = "sum"

        @store.synchronize do
          @store.increment(labels: bucket_label_set, by: 1)
          @store.increment(labels: sum_label_set, by: value)
        end
      end

      # Returns a hash with all the buckets plus +Inf (count) plus Sum for the given label set
      def get(labels: {})
        base_label_set = label_set_for(labels)

        all_buckets = buckets + ["+Inf", "sum"]

        @store.synchronize do
          all_buckets.each_with_object({}) do |upper_limit, acc|
            acc[upper_limit.to_s] = @store.get(labels: base_label_set.merge(le: upper_limit.to_s))
          end.tap do |acc|
            accumulate_buckets(acc)
          end
        end
      end

      # Returns all label sets with their values expressed as hashes with their buckets
      def values
        values = @store.all_values

        result = values.each_with_object({}) do |(label_set, v), acc|
          actual_label_set = label_set.reject{|l| l == :le }
          acc[actual_label_set] ||= @buckets.map{|b| [b.to_s, 0.0]}.to_h
          acc[actual_label_set][label_set[:le].to_s] = v
        end

        result.each do |(_label_set, v)|
          accumulate_buckets(v)
        end
      end

      def init_label_set(labels)
        base_label_set = label_set_for(labels)

        @store.synchronize do
          (buckets + ["+Inf", "sum"]).each do |bucket|
            @store.set(labels: base_label_set.merge(le: bucket.to_s), val: 0)
          end
        end
      end

      private

      # Modifies the passed in parameter
      def accumulate_buckets(h)
        bucket_acc = 0
        buckets.each do |upper_limit|
          bucket_value = h[upper_limit.to_s]
          h[upper_limit.to_s] += bucket_acc
          bucket_acc += bucket_value
        end

        inf_value = h["+Inf"] || 0.0
        h["+Inf"] = inf_value + bucket_acc
      end

      def reserved_labels
        [:le]
      end

      def sorted?(bucket)
        bucket.each_cons(2).all? { |i, j| i <= j }
      end
    end
  end
end
