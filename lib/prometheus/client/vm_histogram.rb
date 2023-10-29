# encoding: UTF-8

require 'prometheus/client/metric'

module Prometheus
  module Client
    # TODO: description
    class VmHistogram < Metric
      attr_reader :buckets, :non_nil_buckets

      E10MIN = -9
      E10MAX = 18
      BUCKETS_PER_DECIMAL = 18
      DECIMAL_BUCKETS_COUNT = E10MAX - E10MIN
      BUCKETS_COUNT = DECIMAL_BUCKETS_COUNT * BUCKETS_PER_DECIMAL
      BUCKETS_MULTIPLIER = 10**(1.0 / BUCKETS_PER_DECIMAL)
      VMRANGES ||= begin
        h = {}
        value = 10**E10MIN
        # TODO: check memory if add .to_sym
        range_start = format('%.3e', value)

        BUCKETS_COUNT.times do |i|
          value *= BUCKETS_MULTIPLIER
          range_end = format('%.3e', value)
          h[i] = "#{range_start}...#{range_end}"
          range_start = range_end
        end

        h
      end

      # Offer a way to manually specify buckets
      def initialize(name,
                     docstring:,
                     labels: [],
                     preset_labels: {},
                     buckets: [],
                     store_settings: {})
        puts "\nWARNING: VM histogram ignores passed buckets, accepts only for compatibility" unless buckets.empty?

        @buckets = ['sum', 'count']
        # TODO: this should take into account labels
        @non_nil_buckets = {}

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
                                    # buckets: @buckets,
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
      # or zero. A negative value is accepted but prevents current
      # versions of Prometheus from properly detecting counter resets
      # in the sum of observations. See
      # https://prometheus.io/docs/practices/histograms/#count-and-sum-of-observations
      # for details.
      def observe(value, labels: {})
        return if value.to_f.nan? || value.negative?

        # bucket = buckets.find {|upper_limit| upper_limit >= value  }
        # bucket = buckets.find_or_create {|upper_limit| upper_limit >= value  }
        # bucket = "+Inf" if bucket.nil?

        float_bucket_id = (Math.log10(value) - E10MIN) * BUCKETS_PER_DECIMAL

        bucket_id = float_bucket_id.to_i

        # TODO: edge case where value is equal to one of 10^n
        # if float_bucket_id == bucket_id.to_f && bucket_id.positive?
        #   bucket_id -= 1
        # end

        # decimal_bucket_id = bucket_id / BUCKETS_PER_DECIMAL
        # offset = bucket_id % BUCKETS_PER_DECIMAL

        base_label_set = label_set_for(labels)

        # This is basically faster than doing `.merge`
        bucket_label_set = base_label_set.dup
        bucket_label_set[:vmrange] = VMRANGES[bucket_id]

        @non_nil_buckets[bucket_label_set[:vmrange]] = nil # just to track non empty buckets

        base_label_set_copy = base_label_set.dup

        @store.synchronize do
          @store.increment(labels: bucket_label_set, by: 1)

          # TODO: optimize to avoid using .merge, its slow
          @store.increment(labels: base_label_set_copy.merge({ le: 'sum' }), by: value)
          @store.increment(labels: base_label_set_copy.merge({ le: 'count' }), by: 1)
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

        vmrange_buckets = values.map { |hash_key, _v| hash_key[:vmrange] if hash_key.key? :vmrange }.compact
        all_buckets = vmrange_buckets + @buckets

        values.each_with_object({}) do |(label_set, v), acc|
          actual_label_set = label_set.reject{|l| [:vmrange, :le].include? l }
          acc[actual_label_set] ||= all_buckets.map{|b| [b.to_s, 0.0]}.to_h
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
