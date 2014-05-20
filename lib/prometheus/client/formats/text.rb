# encoding: UTF-8

module Prometheus
  module Client
    module Formats
      # Text format is human readable mainly used for manual inspection.
      module Text
        MEDIA_TYPE   = 'text/plain'
        VERSION      = '0.0.4'
        CONTENT_TYPE = %Q(#{MEDIA_TYPE}; version=#{VERSION})

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
              representation(metric, set, value) { |l| lines << l }
            end
          end

          # there must be a trailing delimiter
          (lines << nil).join(DELIMITER)
        end

        private

        def self.representation(metric, set, value)
          if metric.type == :summary
            value.each do |q, v|
              yield metric(metric.name, labels(set.merge(quantile: q)), v)
            end

            l = labels(set)
            yield metric("#{metric.name}_sum", l, value.sum)
            yield metric("#{metric.name}_total", l, value.total)
          else
            yield metric(metric.name, labels(set), value)
          end
        end

        def self.metric(name, labels, value)
          format(METRIC_LINE, name, labels, value)
        end

        def self.labels(set)
          return if set.empty?

          strings = set.each_with_object([]) do |(key, value), memo|
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
