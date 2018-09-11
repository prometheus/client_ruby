# encoding: UTF-8

require 'thread'
require 'prometheus/client/label_set_validator'

module Prometheus
  module Client
    # Metric
    class Metric
      attr_reader :name, :docstring, :preset_labels

      def initialize(name, docstring:, labels: [], preset_labels: {})
        @mutex = Mutex.new
        @validator = LabelSetValidator.new(expected_labels: labels,
                                           reserved_labels: reserved_labels)
        @values = Hash.new { |hash, key| hash[key] = default }

        validate_name(name)
        validate_docstring(docstring)
        @validator.valid?(labels)
        @validator.valid?(preset_labels)

        @name = name
        @docstring = docstring
        @preset_labels = preset_labels
      end

      # Returns the value for the given label set
      def get(labels: {})
        label_set = label_set_for(labels)
        @values[label_set]
      end

      # Returns all label sets with their values
      def values
        synchronize do
          @values.each_with_object({}) do |(labels, value), memo|
            memo[labels] = value
          end
        end
      end

      private

      def reserved_labels
        []
      end

      def default
        nil
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
        @validator.validate(preset_labels.merge(labels))
      end

      def synchronize
        @mutex.synchronize { yield }
      end
    end
  end
end
