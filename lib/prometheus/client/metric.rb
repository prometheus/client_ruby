require 'thread'
require 'prometheus/client/label_set'

module Prometheus
  module Client
    # Metric
    class Metric
      def initialize
        @mutex = Mutex.new
        @values = Hash.new(default)
      end

      # Default value
      def default
        nil
      end

      # Returns the metric type
      def type
        raise NotImplementedError
      end

      # Returns all values
      def value
        @values.map do |labels, value|
          { :labels => labels, :value => value }
        end
      end

      # Returns the value for the given label set
      def get(labels = {})
        @values[label_set_for(labels)]
      end

      # Sets the value for the given label set
      def set(labels, value)
        @values[label_set_for(labels)] = value
      end

      # Generates JSON representation
      def to_json(*json)
        {
          'type' => type,
          'value' => value
        }.to_json(*json)
      end

    protected

      def label_set_for(labels)
        LabelSet.new(labels)
      end

      def synchronize(&block)
        @mutex.synchronize(&block)
      end
    end
  end
end
