# frozen_string_literal: true

require 'prometheus/client/metric'

module Prometheus
  module Client
    # A histogram samples observations (usually things like request durations
    # or response sizes) and counts them in configurable buckets. It also
    # provides a total count and sum of all observed values.
    class HistogramFixed < Metric
      # DEFAULT_BUCKETS are the default Histogram buckets. The default buckets
      # are tailored to broadly measure the response time (in seconds) of a
      # network service. (From DefBuckets client_golang)
      DEFAULT_BUCKETS = [
        0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10
      ].freeze
      INF = '+Inf'
      SUM = 'sum'

      attr_reader :buckets, :bucket_strings

      # Offer a way to manually specify buckets
      def initialize(name,
                     docstring:,
                     labels: [],
                     preset_labels: {},
                     buckets: DEFAULT_BUCKETS,
                     store_settings: {})
        raise ArgumentError, 'Unsorted buckets, typo?' unless sorted?(buckets)

        @buckets = buckets
        @bucket_strings = buckets.map(&:to_s) # This is used to avoid calling `to_s` multiple times

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
        base_label_set = label_set_for(labels) # Pottentially can raise, so it should be first
        bucket_idx = buckets.bsearch_index { |upper_limit| upper_limit >= value }
        bucket_str = bucket_idx == nil ? INF : bucket_strings[bucket_idx]

        # This is basically faster than doing `.merge`
        bucket_label_set = base_label_set.dup
        bucket_label_set[:le] = bucket_str

        @store.synchronize do
          @store.increment(labels: bucket_label_set, by: 1)
          @store.increment(labels: base_label_set, by: value)
        end
      end

      # Returns a hash with all the buckets plus +Inf (count) plus Sum for the given label set
      def get(labels: {})
        base_label_set = label_set_for(labels)

        all_buckets = buckets + [INF, SUM]

        @store.synchronize do
          all_buckets.each_with_object(Hash.new(0.0)) do |upper_limit, acc|
            acc[upper_limit.to_s] = @store.get(labels: base_label_set.merge(le: upper_limit.to_s))
          end.tap do |acc|
            accumulate_buckets!(acc)
          end
        end
      end

      # Returns all label sets with their values expressed as hashes with their buckets
      def values
        values = @store.all_values
        default_buckets = Hash.new(0.0)
        bucket_strings.each { |b| default_buckets[b] = 0.0 }

        result = values.each_with_object({}) do |(label_set, v), acc|
          actual_label_set = label_set.except(:le)
          acc[actual_label_set] ||= default_buckets.dup
          acc[actual_label_set][label_set[:le]] = v
        end

        result.each_value { |v| accumulate_buckets!(v) }
      end

      def init_label_set(labels)
        base_label_set = label_set_for(labels)

        @store.synchronize do
          (buckets + [INF, SUM]).each do |bucket|
            @store.set(labels: base_label_set.merge(le: bucket.to_s), val: 0)
          end
        end
      end

      private

      # Modifies the passed in parameter
      def accumulate_buckets!(h)
        accumulator = 0

        bucket_strings.each do |upper_limit|
          accumulator = (h[upper_limit] += accumulator)
        end

        h[INF] += accumulator
      end

      RESERVED_LABELS = [:le].freeze
      private_constant :RESERVED_LABELS
      def reserved_labels
        RESERVED_LABELS
      end

      def sorted?(bucket)
        # This is faster than using `each_cons` and `all?`
        bucket == bucket.sort
      end

      def label_set_for(labels)
        @label_set_for ||= Hash.new do |hash, key|
          _labels = key.transform_values(&:to_s)
          _labels = @validator.validate_labelset_new!(preset_labels.merge(_labels))
          _labels[:le] = SUM # We can cache this, because it's always the same
          hash[key] = _labels
        end

        @label_set_for[labels]
      end
    end
  end
end
