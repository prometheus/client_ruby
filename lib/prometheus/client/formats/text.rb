# encoding: UTF-8

module Prometheus
  module Client
    module Formats
      # Text format is human readable mainly used for manual inspection.
      module Text
        MEDIA_TYPE   = 'text/plain'.freeze
        VERSION      = '0.0.4'.freeze
        CONTENT_TYPE = "#{MEDIA_TYPE}; version=#{VERSION}".freeze

        METRIC_LINE = '%s%s %s'.freeze
        TYPE_LINE   = '# TYPE %s %s'.freeze
        HELP_LINE   = '# HELP %s %s'.freeze

        LABEL     = '%s="%s"'.freeze
        SEPARATOR = ','.freeze
        DELIMITER = "\n".freeze

        REGEX   = { doc: /[\n\\]/, label: /[\n\\"]/ }.freeze
        REPLACE = { "\n" => '\n', '\\' => '\\\\', '"' => '\"' }.freeze

        def self.marshal(registry)
          lines = []

          registry.metrics.each do |metric|
            lines << format(TYPE_LINE, metric.name, metric.type)
            lines << format(HELP_LINE, metric.name, escape(metric.docstring))

            metric.values.each do |label_set, value|
              representation(metric, label_set, value) { |l| lines << l }
            end
          end

          # there must be a trailing delimiter
          (lines << nil).join(DELIMITER)
        end

        class << self
          private

          def representation(metric, label_set, value, &block)
            set = metric.base_labels.merge(label_set)

            if metric.type == :summary
              summary(metric.name, set, value, &block)
            elsif metric.type == :histogram
              histogram(metric.name, set, value, &block)
            else
              yield metric(metric.name, labels(set), value)
            end
          end

          def summary(name, set, value)
            value.each do |q, v|
              yield metric(name, labels(set.merge(quantile: q)), v)
            end

            l = labels(set)
            yield metric("#{name}_sum", l, value.sum)
            yield metric("#{name}_count", l, value.total)
          end

          def histogram(name, set, value)
            value.each do |q, v|
              yield metric(name, labels(set.merge(le: q)), v)
            end
            yield metric(name, labels(set.merge(le: '+Inf')), value.total)

            l = labels(set)
            yield metric("#{name}_sum", l, value.sum)
            yield metric("#{name}_count", l, value.total)
          end

          def metric(name, labels, value)
            format(METRIC_LINE, name, labels, value)
          end

          def labels(set)
            return if set.empty?

            strings = set.each_with_object([]) do |(key, value), memo|
              memo << format(LABEL, key, escape(value, :label))
            end

            "{#{strings.join(SEPARATOR)}}"
          end

          def escape(string, format = :doc)
            string.to_s.gsub(REGEX[format], REPLACE)
          end
        end
      end
    end
  end
end
