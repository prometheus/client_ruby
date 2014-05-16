# encoding: UTF-8

module Prometheus
  module Client
    module Formats
      # Text format is human readable mainly used for manual inspection.
      module Text
        VERSION = '0.0.4'
        TYPE    = 'text/plain; version=' + VERSION

        METRIC_LINE = '%s%s %s'
        TYPE_LINE   = '# TYPE %s %s'
        HELP_LINE   = '# HELP %s %s'

        LABEL     = '%s="%s"'
        SEPARATOR = ','
        DELIMITER = "\n"

        REGEX   = { doc: /[\n\\]/, label: /[\n\\"]/ }
        REPLACE = { "\n" => '\n', '\\' => '\\\\', '"' => '\"' }

        def self.marshal(registry)
          lines = []

          registry.metrics.each do |metric|
            lines << format(TYPE_LINE, metric.name, metric.type)
            lines << format(HELP_LINE, metric.name, escape(metric.docstring))

            metric.values.each do |label_set, value|
              set = metric.base_labels.merge(label_set)
              representation(metric.name, set, value) { |l| lines << l }
            end
          end

          # there must be a trailing delimiter
          (lines << nil).join(DELIMITER)
        end

        private

        def self.representation(name, set, value)
          if value.is_a?(Hash)
            value.each do |quantile, v|
              l = labels(set.merge(quantile: quantile))
              yield format(METRIC_LINE, name, l, v)
            end
          else
            yield format(METRIC_LINE, name, labels(set), value)
          end
        end

        def self.labels(set)
          return if set.empty?

          strings = set.reduce([]) do |memo, (key, value)|
            memo << format(LABEL, key, escape(value, :label))
          end

          "{#{strings.join(SEPARATOR)}}"
        end

        def self.escape(string, format = :doc)
          string.to_s.gsub(REGEX[format], REPLACE)
        end
      end
    end
  end
end
