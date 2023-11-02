# encoding: UTF-8

require 'prometheus/client/metric'

module Prometheus
  module Client
    # A histogram samples observations (usually things like request durations
    # or response sizes) and counts them in dynamic VictoriaMetrics buckets. It also
    # provides a total count and sum of all observed values.
    class VmHistogram < Metric
      attr_reader :buckets

      E10MIN = -9
      E10MAX = 18
      BUCKETS_PER_DECIMAL = 18
      DECIMAL_BUCKETS_COUNT = E10MAX - E10MIN
      BUCKETS_COUNT = DECIMAL_BUCKETS_COUNT * BUCKETS_PER_DECIMAL
      BUCKETS_MULTIPLIER = 10**(1.0 / BUCKETS_PER_DECIMAL)
      VMRANGES ||= begin
        h = {}
        value = 10**E10MIN
        range_start = format('%.3e', value)

        BUCKETS_COUNT.times do |i|
          value *= BUCKETS_MULTIPLIER
          range_end = format('%.3e', value)
          h[i] = "#{range_start}...#{range_end}"
          range_start = range_end
        end

        # edge case fo zeros
        h[-1] = '0...1.000e-09'

        h
      end

      def initialize(name,
                     docstring:,
                     labels: [],
                     preset_labels: {},
                     buckets: [], # VM histogram ignores passed buckets, accepts only for compatibility
                     store_settings: {})

        @buckets = ['sum', 'count']
        # TODO: this should take into account labels
        @non_nil_buckets = {}
        @base_label_set_cache = {}

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
        :vm_histogram
      end

      # Records a given value. The recorded value is usually positive
      # or zero. A negative value is ignored.
      def observe(value, labels: {})
        return if value.to_f.nan? || value.negative?

        float_bucket_id = (Math.log10(value) - E10MIN) * BUCKETS_PER_DECIMAL

        bucket_id = if float_bucket_id.negative?
          -1
        elsif float_bucket_id > VMRANGES.keys.max
          VMRANGES.keys.max
        else
          float_bucket_id.to_i
        end

        # Edge case for 10^n values, which must go to the lower bucket
        # according to Prometheus logic for `le`-based histograms
        bucket_id -= 1 if (float_bucket_id - bucket_id.to_f).abs < Float::EPSILON && bucket_id.positive?

        base_label_set = label_set_for(labels)

        # OPTIMIZE: probably we also can use cache for vmranges to avoid using .dup every time
        bucket_label_set = base_label_set.dup
        bucket_label_set[:vmrange] = VMRANGES[bucket_id]

        @non_nil_buckets[bucket_label_set[:vmrange]] = nil # just to track non empty buckets

        unless @base_label_set_cache.key? base_label_set
          @base_label_set_cache[base_label_set] = {
            sum: base_label_set.merge({ le: 'sum' }),
            count: base_label_set.merge({ le: 'count' })
          }
        end

        @store.synchronize do
          @store.increment(labels: bucket_label_set, by: 1)
          @store.increment(labels: @base_label_set_cache[base_label_set][:sum], by: value)
          @store.increment(labels: @base_label_set_cache[base_label_set][:count], by: 1)
        end
      end

      def get(labels: {})
        base_label_set = label_set_for(labels)

        all_buckets = @non_nil_buckets.keys + buckets

        @store.synchronize do
          all_buckets.each_with_object({}) do |bucket, acc|
            if @non_nil_buckets.key? bucket
              value = @store.get(labels: base_label_set.merge(vmrange: bucket.to_s))
              acc[bucket.to_s] = value if value.positive?
            else
              acc[bucket.to_s] = @store.get(labels: base_label_set.merge(le: bucket.to_s))
            end
          end
        end
      end

      # Returns all label sets with their values expressed as hashes with their buckets
      def values
        values = @store.all_values

        values.each_with_object({}) do |(label_set, v), acc|
          actual_label_set = label_set.reject { |l| [:vmrange, :le].include? l }
          acc[actual_label_set] ||= {}
          label_name = label_set[:vmrange] || label_set[:le]
          acc[actual_label_set][label_name.to_s] = v
        end
      end

      def init_label_set(labels)
        base_label_set = label_set_for(labels)

        @store.synchronize do
          @buckets.each do |bucket|
            @store.set(labels: base_label_set.merge(le: bucket.to_s), val: 0)
          end
        end
      end

      private

      def reserved_labels
        [:vmrange]
      end
    end
  end
end
