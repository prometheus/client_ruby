# encoding: UTF-8

require 'thread'
require 'prometheus/client/label_set_validator'

module Prometheus
  module Client
    # Metric
    class Metric
      attr_reader :name, :docstring, :base_labels

      def initialize(name, docstring, base_labels = {})
        @mutex = Mutex.new
        @validator = LabelSetValidator.new
        @values = Hash.new { |hash, key| hash[key] = default }

        validate_name(name)
        validate_docstring(docstring)
        @validator.valid?(base_labels)

        @name = name
        @docstring = docstring
        @base_labels = base_labels
      end

      # Returns the value for the given label set
      def get(labels = {})
        @validator.valid?(labels)

        @values[labels]
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

      def default
        nil
      end

      def validate_name(name)
        return true if name.is_a?(Symbol)

        raise ArgumentError, 'given name must be a symbol'
      end

      def validate_docstring(docstring)
        return true if docstring.respond_to?(:empty?) && !docstring.empty?

        raise ArgumentError, 'docstring must be given'
      end

      def label_set_for(labels)
        @validator.validate(labels)
      end

      def synchronize
        @mutex.synchronize { yield }
      end
    end
  end
end
