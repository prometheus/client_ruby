require 'json'

module Prometheus
  module Client
    module Formats
      module JSON
        VERSION = '0.0.2'
        TYPE    = 'application/json; schema="prometheus/telemetry"; version=' + VERSION

        def self.marshal(registry)
          registry.metrics.map do |metric|
            {
              baseLabels: metric.base_labels.merge(__name__: metric.name),
              docstring:  metric.docstring,
              metric: {
                type:  metric.type,
                value: metric.values.map { |labels, value|
                  { labels: labels, value: value }
                }
              }
            }
          end.to_json
        end

        def self.unmarshal(text)
          raise NotImplementedError
        end

      end
    end
  end
end
