# encoding: UTF-8

require 'prometheus/client/metric'
require 'prometheus/client/summary/quantile'

module Prometheus
  module Client
    # Summary is an accumulator for samples. It captures Numeric data and
    # provides the total count, sum of observations, and configurable
    # quantile estimates.
    class Summary < Metric
      attr_reader :objectives

      DEFAULT_MAX_AGE = 600
      DEFAULT_AGE_BUCKETS = 5

      def initialize(name,
                     docstring:,
                     labels: [],
                     preset_labels: {},
                     objectives: {},
                     max_age: DEFAULT_MAX_AGE,
                     age_buckets: DEFAULT_AGE_BUCKETS,
                     store_settings: {})
        @objectives = objectives
        @max_age = max_age
        @age_buckets = age_buckets
        @estimators = {}
        @estimator_lock = Monitor.new

        super(name,
              docstring: docstring,
              labels: labels,
              preset_labels: preset_labels,
              store_settings: store_settings)
      end

      def with_labels(labels)
        new_metric = self.class.new(name,
                                    docstring: docstring,
                                    labels: @labels,
                                    preset_labels: preset_labels.merge(labels),
                                    objectives: @objectives,
                                    max_age: @max_age,
                                    age_buckets: @age_buckets,
                                    store_settings: @store_settings)

        new_metric.replace_internal_store(@store)
        new_metric.replace_estimators(@estimators, @estimator_lock)

        new_metric
      end

      def type
        :summary
      end

      # Records a given value. The recorded value is usually positive
      # or zero. A negative value is accepted but prevents current
      # versions of Prometheus from properly detecting counter resets
      # in the sum of observations. See
      # https://prometheus.io/docs/practices/histograms/#count-and-sum-of-observations
      # for details.
      def observe(value, labels: {})
        base_label_set = label_set_for(labels)

        @store.synchronize do
          @store.increment(labels: base_label_set.merge(quantile: "count"), by: 1)
          @store.increment(labels: base_label_set.merge(quantile: "sum"), by: value)
        end

        unless @objectives.empty?
          estimator = estimator_for(base_label_set)
          estimator.observe(value)
        end
      end

      # Returns a hash with "sum", "count", and quantile keys
      def get(labels: {})
        base_label_set = label_set_for(labels)

        internal_counters = ["count", "sum"]

        result = @store.synchronize do
          internal_counters.each_with_object({}) do |counter, acc|
            acc[counter] = @store.get(labels: base_label_set.merge(quantile: counter))
          end
        end

        unless @objectives.empty?
          estimator = estimator_for(base_label_set)
          @objectives.each_key do |quantile|
            result[quantile.to_s] = estimator.query(quantile)
          end
        end

        result
      end

      # Returns all label sets with their values expressed as hashes with their sum/count
      def values
        values = @store.all_values

        result = values.each_with_object({}) do |(label_set, v), acc|
          actual_label_set = label_set.reject{|l| l == :quantile }
          acc[actual_label_set] ||= { "count" => 0.0, "sum" => 0.0 }
          acc[actual_label_set][label_set[:quantile]] = v
        end

        unless @objectives.empty?
          result.each do |label_set, hash|
            estimator = estimator_for(label_set)
            @objectives.each_key do |quantile|
              hash[quantile.to_s] = estimator.query(quantile)
            end
          end
        end

        result
      end

      def init_label_set(labels)
        base_label_set = label_set_for(labels)

        @store.synchronize do
          @store.set(labels: base_label_set.merge(quantile: "count"), val: 0)
          @store.set(labels: base_label_set.merge(quantile: "sum"), val: 0)
        end
      end

      protected

      def replace_estimators(estimators, lock)
        @estimators = estimators
        @estimator_lock = lock
      end

      private

      def reserved_labels
        [:quantile]
      end

      def estimator_for(label_set)
        @estimator_lock.synchronize do
          @estimators[label_set] ||= ::Prometheus::Client::Quantile::TimeWindowEstimator.new(
            objectives: @objectives,
            max_age: @max_age,
            age_buckets: @age_buckets,
          )
        end
      end
    end
  end
end
