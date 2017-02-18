# encoding: UTF-8

require 'prometheus/client/valuetype'

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

        def self.marshal_multiprocess(path=ENV['prometheus_multiproc_dir'])
          metrics = {}
          Dir.glob(File.join(path, "*.db")).each do |f|
            parts = File.basename(f).split("_")
            type = parts[0].to_sym
            d = MmapedDict.new(f)
            d.all_values.each do |key, value|
              metric_name, name, labelnames, labelvalues = JSON.parse(key)
              metric = metrics.fetch(metric_name, {
                metric_name: metric_name,
                help: 'Multiprocess metric',
                type: type,
                samples: [],
              })
              if type == :gauge
                pid = parts[2][0..-3]
                metric[:multiprocess_mode] = parts[1]
                metric[:samples] += [[name, labelnames.zip(labelvalues) + [['pid', pid]], value]]
              else
                # The duplicates and labels are fixed in the next for.
                metric[:samples] += [[name, labelnames.zip(labelvalues), value]]
              end
              metrics[metric_name] = metric
            end
            d.close
          end

          metrics.each_value do |metric|
            samples = {}
            buckets = {}
            metric[:samples].each do |name, labels, value|
              case metric[:type]
              when :gauge
                without_pid = labels.select{ |l| l[0] != 'pid' }
                case metric[:multiprocess_mode]
                when 'min'
                  s = samples.fetch([name, without_pid], value)
                  samples[[name, without_pid]] = [s, value].min
                when 'max'
                  s = samples.fetch([name, without_pid], value)
                  samples[[name, without_pid]] = [s, value].max
                when 'livesum'
                  s = samples.fetch([name, without_pid], 0.0)
                  samples[[name, without_pid]] = s + value
                else # all/liveall
                  samples[[name, labels]] = value
                end
              when :histogram
                bucket = labels.select{|l| l[0] == 'le' }.map {|k, v| v.to_f}.first
                if bucket
                  without_le = labels.select{ |l| l[0] != 'le' }
                  b = buckets.fetch(without_le, {})
                  v = b.fetch(bucket, 0.0) + value
                  if !buckets.has_key?(without_le)
                    buckets[without_le] = {}
                  end
                  buckets[without_le][bucket] = v
                else
                  s = samples.fetch([name, labels], 0.0)
                  samples[[name, labels]] = s + value
                end
              else
                # Counter and Summary.
                s = samples.fetch([name, without_pid], 0.0)
                samples[[name, without_pid]] = s + value
              end

              if metric[:type] == :histogram
                buckets.each do |labels, values|
                  acc = 0.0
                  values.sort.each do |bucket, value|
                    acc += value
                    # TODO: handle Infinity
                    samples[[metric[:metric_name] + '_bucket', labels + [['le', bucket.to_s]]]] = acc
                  end
                  samples[[metric[:metric_name] + '_count', labels]] = acc
                end
              end

              metric[:samples] = samples.map do |name_labels, value|
                name, labels = name_labels
                [name, labels.to_h, value]
              end
            end
          end

          output = ''
          metrics.each do |name, metric|
            output += "# HELP #{name} #{metric[:help]}\n"
            output += "# TYPE #{name} #{metric[:type].to_s}\n"
            metric[:samples].each do |metric_name, labels, value|
              if !labels.empty?
                labelstr = '{' + labels.sort.map { |k, v| "#{k}='#{v}'" }.join(',') + '}'
              else
                labelstr = ''
              end
              output += "#{metric_name}#{labelstr} #{value}\n"
            end
          end
          output
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
              yield metric(metric.name, labels(set), value.get)
            end
          end

          def summary(name, set, value)
            value.each do |q, v|
              yield metric(name, labels(set.merge(quantile: q)), v.get)
            end

            l = labels(set)
            yield metric("#{name}_sum", l, value.sum.get)
            yield metric("#{name}_count", l, value.total.get)
          end

          def histogram(name, set, value)
            value.each do |q, v|
              yield metric(name, labels(set.merge(le: q)), v.get)
            end
            yield metric(name, labels(set.merge(le: '+Inf')), value.total.get)

            l = labels(set)
            yield metric("#{name}_sum", l, value.sum.get)
            yield metric("#{name}_count", l, value.total.get)
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
