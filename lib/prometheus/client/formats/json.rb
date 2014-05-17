# encoding: UTF-8

require 'json'

module Prometheus
  module Client
    module Formats
      # JSON format is a deprecated, human-readable format to expose the state
      # of a given registry.
      module JSON
        VERSION = '0.0.2'
        SCHEMA  = 'schema="prometheus/telemetry"'
        TYPE    = "application/json; #{SCHEMA}; version=#{VERSION}"
        MAPPING = { :summary => :histogram }

        def self.marshal(registry)
          registry.metrics.map do |metric|
            {
              baseLabels: metric.base_labels.merge(__name__: metric.name),
              docstring:  metric.docstring,
              metric: {
                type:  MAPPING[metric.type] || metric.type,
                value: metric.values.map { |l, v| { labels: l, value: v } },
              },
            }
          end.to_json
        end
      end
    end
  end
end
