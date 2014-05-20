# encoding: UTF-8

require 'thread'
require 'prometheus/client/label_set'

module Prometheus
  module Client
    # Metric
    class Metric
      attr_reader :name, :docstring, :base_labels

      def initialize(name, docstring, base_labels = {})
        unless name.is_a?(Symbol)
          fail ArgumentError, 'given name must be a symbol'
        end

        if !docstring.respond_to?(:empty?) || docstring.empty?
          fail ArgumentError, 'docstring must be given'
        end

        @name, @docstring = name, docstring
        @base_labels = LabelSet.new(base_labels)
        @mutex = Mutex.new
        @values = Hash.new { |hash, key| hash[key] = default }
      end

      # Returns the metric type
      def type
        fail NotImplementedError
      end

      # Returns the value for the given label set
      def get(labels = {})
        @values[label_set_for(labels)]
      end

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

      def label_set_for(labels)
        LabelSet.new(labels)
      end

      def synchronize(&block)
        @mutex.synchronize(&block)
      end
    end
  end
end
