# encoding: UTF-8

require 'thread'
require 'prometheus/client/label_set_validator'

module Prometheus
  module Client
    # Metric
    class Metric
      attr_reader :name, :docstring, :labels, :preset_labels

      def initialize(name,
                     docstring:,
                     labels: [],
                     preset_labels: {},
                     store_settings: {})

        validate_name(name)
        validate_docstring(docstring)
        @validator = LabelSetValidator.new(expected_labels: labels,
                                           reserved_labels: reserved_labels)
        @validator.validate_symbols!(labels)
        @validator.validate_symbols!(preset_labels)

        @labels = labels
        @store_settings = store_settings

        @name = name
        @docstring = docstring
        @preset_labels = stringify_values(preset_labels)

        @all_labels_preset = false
        if preset_labels.keys.length == labels.length
          @validator.validate_labelset!(preset_labels)
          @all_labels_preset = true
        end

        @store = Prometheus::Client.config.data_store.for_metric(
          name,
          metric_type: type,
          metric_settings: store_settings
        )

        # WARNING: Our internal store can be replaced later by `with_labels`
        # Everything we do after this point needs to still work if @store gets replaced
        init_label_set({}) if labels.empty?
      end

      protected def replace_internal_store(new_store)
        @store = new_store
      end


      # Returns the value for the given label set
      def get(labels: {})
        label_set = label_set_for(labels)
        @store.get(labels: label_set)
      end

      def with_labels(labels)
        new_metric = self.class.new(name,
                                     docstring: docstring,
                                     labels: @labels,
                                     preset_labels: preset_labels.merge(labels),
                                     store_settings: @store_settings)

        # The new metric needs to use the same store as the "main" declared one, otherwise
        # any observations on that copy with the pre-set labels won't actually be exported.
        new_metric.replace_internal_store(@store)

        new_metric
      end

      def init_label_set(labels)
        @store.set(labels: label_set_for(labels), val: 0)
      end

      # Returns all label sets with their values
      def values
        @store.all_values
      end

      private

      def reserved_labels
        []
      end

      def validate_name(name)
        unless name.is_a?(Symbol)
          raise ArgumentError, 'metric name must be a symbol'
        end
        unless name.to_s =~ /\A[a-zA-Z_:][a-zA-Z0-9_:]*\Z/
          msg = 'metric name must match /[a-zA-Z_:][a-zA-Z0-9_:]*/'
          raise ArgumentError, msg
        end
      end

      def validate_docstring(docstring)
        return true if docstring.respond_to?(:empty?) && !docstring.empty?

        raise ArgumentError, 'docstring must be given'
      end

      def label_set_for(labels)
        # We've already validated, and there's nothing to merge. Save some cycles
        return preset_labels if @all_labels_preset && labels.empty?
        labels = stringify_values(labels)
        @validator.validate_labelset!(preset_labels.merge(labels))
      end

      def stringify_values(labels)
        stringified = {}
        labels.each { |k,v| stringified[k] = v.to_s }

        stringified
      end
    end
  end
end
