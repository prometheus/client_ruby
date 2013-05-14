require 'prometheus/client/label_set'

module Prometheus
  module Client
    # Metric Container
    class Container
      attr_reader :name, :docstring, :metric, :base_labels

      def initialize(name, docstring, metric, base_labels)
        @name = name
        @docstring = docstring
        @metric = metric
        @base_labels = LabelSet.new(base_labels)
      end

      def to_json(*json)
        {
          'baseLabels' => base_labels.merge(:name => name),
          'docstring'  => docstring,
          'metric'     => metric
        }.to_json(*json)
      end

    end
  end
end
