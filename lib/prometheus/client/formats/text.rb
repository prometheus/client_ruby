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
          if Prometheus::Client.config.data_store.is_a?(Prometheus::Client::DataStores::DirectFileStore)
            marshal_direct_file_store(registry)
          else
            marshal_normal_stores(registry)
          end
        end

        class << self
          private

          def marshal_normal_stores(registry)
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

          def marshal_direct_file_store(registry)
            lines = []

            all_metrics_values = Prometheus::Client.config.data_store.all_raw_metrics_values
            values_per_metrics = {}

            all_metrics_values.each do |label_set, values|
              metric_name = label_set[:___metric_name]
              label_set = label_set.except(:___metric_name)

              values_per_metrics[metric_name] ||= {}
              values_per_metrics[metric_name][label_set] ||= []
              values_per_metrics[metric_name][label_set] += values
              # Hash.new { |hash, key| hash[key] = Hash.new { |hash, key| hash[key] = 0.0 } }
            end

            registry.metrics.each do |metric|
              lines << format(TYPE_LINE, metric.name, metric.type)
              lines << format(HELP_LINE, metric.name, escape(metric.docstring))

              metric_values = values_per_metrics[metric.name.to_s]
              aggregated_values = Hash.new { |hash, key| hash[key] = 0.0 }
              metric_values.each_with_object(aggregated_values) do |(label_set, values), acc|
                acc[label_set] = Prometheus::Client::DataStores::DirectFileStore::ValuesAggregator.aggregate_values(
                  values, metric.store.values_aggregation_mode
                )
              end

              formatted_metric_values = metric.values(aggregated_values)
              formatted_metric_values.each do |label_set, value|
                representation(metric, label_set, value) { |l| lines << l }
              end
            end

            # there must be a trailing delimiter
            (lines << nil).join(DELIMITER)
          end

          def representation(metric, label_set, value, &block)
            if metric.type == :summary
              summary(metric.name, label_set, value, &block)
            elsif metric.type == :histogram
              histogram(metric.name, label_set, value, &block)
            else
              yield metric(metric.name, labels(label_set), value)
            end
          end

          def summary(name, set, value)
            l = labels(set)
            yield metric("#{name}_sum", l, value["sum"])
            yield metric("#{name}_count", l, value["count"])
          end

          def histogram(name, set, value)
            bucket = "#{name}_bucket"
            value.each do |q, v|
              next if q == "sum"
              yield metric(bucket, labels(set.merge(le: q)), v)
            end

            l = labels(set)
            yield metric("#{name}_sum", l, value["sum"])
            yield metric("#{name}_count", l, value["+Inf"])
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
