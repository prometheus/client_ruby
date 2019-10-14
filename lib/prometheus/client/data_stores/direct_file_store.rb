require 'fileutils'
require "cgi"

module Prometheus
  module Client
    module DataStores
      # Stores data in binary files, one file per process and per metric.
      # This is generally the recommended store to use to deal with pre-fork servers and
      # other "multi-process" scenarios.
      #
      # Each process will get a file for a metric, and it will manage its contents by
      # storing keys next to binary-encoded Floats, and keeping track of the offsets of
      # those Floats, to be able to update them directly as they increase.
      #
      # When exporting metrics, the process that gets scraped by Prometheus  will find
      # all the files that apply to a metric, read their contents, and aggregate them
      # (generally that means SUMming the values for each labelset).
      #
      # In order to do this, each Metric needs an `:aggregation` setting, specifying how
      # to aggregate the multiple possible values we can get for each labelset. By default,
      # they are `SUM`med, which is what most use cases call for (counters and histograms,
      # for example).
      # However, for Gauges, it's possible to set `MAX` or `MIN` as aggregation, to get
      # the highest value of all the processes / threads.

      class DirectFileStore
        class InvalidStoreSettingsError < StandardError; end
        AGGREGATION_MODES = [MAX = :max, MIN = :min, SUM = :sum, ALL = :all]
        DEFAULT_METRIC_SETTINGS = { aggregation: SUM }
        DEFAULT_GAUGE_SETTINGS = { aggregation: ALL }

        def initialize(dir:, separate_files_per_metric: true)
          @store_settings = { dir: dir,
                              separate_files_per_metric: separate_files_per_metric }
          FileUtils.mkdir_p(dir)
        end

        def for_metric(metric_name, metric_type:, metric_settings: {})
          default_settings = DEFAULT_METRIC_SETTINGS
          if metric_type == :gauge
            default_settings = DEFAULT_GAUGE_SETTINGS
          end

          settings = default_settings.merge(metric_settings)
          validate_metric_settings(settings)

          MetricStore.new(metric_name: metric_name,
                          store_settings: @store_settings,
                          metric_settings: settings)
        end

        private

        def validate_metric_settings(metric_settings)
          unless metric_settings.has_key?(:aggregation) &&
            AGGREGATION_MODES.include?(metric_settings[:aggregation])
            raise InvalidStoreSettingsError,
                  "Metrics need a valid :aggregation key"
          end

          unless (metric_settings.keys - [:aggregation]).empty?
            raise InvalidStoreSettingsError,
                  "Only :aggregation setting can be specified"
          end
        end

        class MetricStore
          attr_reader :metric_name, :store_settings

          class << self
            attr_accessor :shared_store_opened_by_pid
            attr_accessor :shared_internal_store
          end

          def initialize(metric_name:, store_settings:, metric_settings:)
            @metric_name = metric_name
            @store_settings = store_settings
            @values_aggregation_mode = metric_settings[:aggregation]

            @lock = Monitor.new
          end

          # Synchronize is used to do a multi-process Mutex, when incrementing multiple
          # values at once, so that the other process, reading the file for export, doesn't
          # get incomplete increments.
          #
          # `in_process_sync`, instead, is just used so that two threads don't increment
          # the same value and get a context switch between read and write leading to an
          # inconsistency
          def synchronize
            in_process_sync do
              internal_store.with_file_lock do
                yield
              end
            end
          end

          def set(labels:, val:)
            in_process_sync do
              internal_store.write_value(store_key(labels), val.to_f)
            end
          end

          def increment(labels:, by: 1)
            key = store_key(labels)
            in_process_sync do
              value = internal_store.read_value(key)
              internal_store.write_value(key, value + by.to_f)
            end
          end

          def get(labels:)
            in_process_sync do
              internal_store.read_value(store_key(labels))
            end
          end

          def all_values
            stores_data = Hash.new{ |hash, key| hash[key] = [] }

            # There's no need to call `synchronize` here. We're opening a second handle to
            # the file, and `flock`ing it, which prevents inconsistent reads
            stores_for_metric.each do |file_path|
              begin
                store = FileMappedDict.new(file_path, true)
                store.all_values.each do |(labelset_qs, v)|
                  # Labels come as a query string, and CGI::parse returns arrays for each key
                  # "foo=bar&x=y" => { "foo" => ["bar"], "x" => ["y"] }
                  # Turn the keys back into symbols, and remove the arrays
                  label_set = CGI::parse(labelset_qs).map do |k, vs|
                    [k.to_sym, vs.first]
                  end.to_h

                  unless @store_settings[:separate_files_per_metric]
                    # All metrics are in the same file. Ignore entries for other metrics
                    next unless label_set[:__metric_name] == metric_name.to_s
                    label_set.delete(:__metric_name)
                  end

                  stores_data[label_set] << v
                end
              ensure
                store.close if store
              end
            end

            # Aggregate all the different values for each label_set
            aggregate_hash = Hash.new { |hash, key| hash[key] = 0.0 }
            stores_data.each_with_object(aggregate_hash) do |(label_set, values), acc|
              acc[label_set] = aggregate_values(values)
            end
          end

          private

          def in_process_sync
            @lock.synchronize { yield }
          end

          def store_key(labels)
            if @values_aggregation_mode == ALL
              labels[:pid] = process_id
            end
            unless @store_settings[:separate_files_per_metric]
              labels[:__metric_name] = metric_name.to_s
            end

            labels.map{|k,v| "#{CGI::escape(k.to_s)}=#{CGI::escape(v.to_s)}"}.join('&')
          end

          def internal_store
            if @store_settings[:separate_files_per_metric]
              individual_metric_internal_store
            else
              all_metrics_shared_internal_store
            end
          end

          def individual_metric_internal_store
            if @store_opened_by_pid != process_id
              @store_opened_by_pid = process_id
              @internal_store = FileMappedDict.new(filemap_filename)
            else
              @internal_store
            end
          end

          def all_metrics_shared_internal_store
            if self.class.shared_store_opened_by_pid != process_id
              self.class.shared_store_opened_by_pid = process_id
              self.class.shared_internal_store = FileMappedDict.new(filemap_filename)
            else
              self.class.shared_internal_store
            end
          end

          # Filename for this metric's PStore (one per process)
          def filemap_filename
            filename = if @store_settings[:separate_files_per_metric]
                         "metric_#{ metric_name }___#{ process_id }.bin"
                       else
                         "metric___all_metrics___#{ process_id }.bin"
                       end
            File.join(@store_settings[:dir], filename)
          end

          def stores_for_metric
            base_filename = if @store_settings[:separate_files_per_metric]
                              "metric_#{ metric_name }___*"
                            else
                              "metric___all_metrics___*"
                            end
            Dir.glob(File.join(@store_settings[:dir], base_filename))
          end

          def process_id
            Process.pid
          end

          def aggregate_values(values)
            if @values_aggregation_mode == SUM
              values.inject { |sum, element| sum + element }
            elsif @values_aggregation_mode == MAX
              values.max
            elsif @values_aggregation_mode == MIN
              values.min
            elsif @values_aggregation_mode == ALL
              values.first
            else
              raise InvalidStoreSettingsError,
                    "Invalid Aggregation Mode: #{ @values_aggregation_mode }"
            end
          end
        end

        private_constant :MetricStore

        # A dict of doubles, backed by an file we access directly a a byte array.
        #
        # The file starts with a 4 byte int, indicating how much of it is used.
        # Then 4 bytes of padding.
        # There's then a number of entries, consisting of a 4 byte int which is the
        # size of the next field, a utf-8 encoded string key, padding to an 8 byte
        # alignment, and then a 8 byte float which is the value.
        class FileMappedDict
          INITIAL_FILE_SIZE = 1024*1024

          attr_reader :capacity, :used, :positions

          def initialize(filename, readonly = false)
            @positions = {}
            @used = 0

            open_file(filename, readonly)
            @used = @f.read(4).unpack('l')[0] if @capacity > 0

            if @used > 0
              # File already has data. Read the existing values
              with_file_lock do
                read_all_values.each do |key, _, pos|
                  @positions[key] = pos
                end
              end
            else
              # File is empty. Init the `used` counter, if we're in write mode
              if !readonly
                @used = 8
                @f.seek(0)
                @f.write([@used].pack('l'))
              end
            end
          end

          # Yield (key, value, pos). No locking is performed.
          def all_values
            with_file_lock do
              read_all_values.map { |k, v, p| [k, v] }
            end
          end

          def read_value(key)
            if !@positions.has_key?(key)
              init_value(key)
            end

            pos = @positions[key]
            @f.seek(pos)
            @f.read(8).unpack('d')[0]
          end

          def write_value(key, value)
            if !@positions.has_key?(key)
              init_value(key)
            end

            pos = @positions[key]
            @f.seek(pos)
            @f.write([value].pack('d'))
            @f.flush
          end

          def close
            @f.close
          end

          def with_file_lock
            @f.flock(File::LOCK_EX)
            yield
          ensure
            @f.flock(File::LOCK_UN)
          end

          private

          def open_file(filename, readonly)
            mode = if readonly
                     "r"
                   elsif File.exist?(filename)
                     "r+b"
                   else
                     "w+b"
                   end

            @f = File.open(filename, mode)
            if @f.size == 0 && !readonly
              resize_file(INITIAL_FILE_SIZE)
            end
            @capacity = @f.size
          end

          def resize_file(new_capacity)
            @f.truncate(new_capacity)
          end

          # Initialize a value. Lock must be held by caller.
          def init_value(key)
            # Pad to be 8-byte aligned.
            padded = key + (' ' * (8 - (key.length + 4) % 8))
            value = [padded.length, padded, 0.0].pack("lA#{padded.length}d")
            while @used + value.length > @capacity
              @capacity *= 2
              resize_file(@capacity)
            end
            @f.seek(@used)
            @f.write(value)
            @used += value.length
            @f.seek(0)
            @f.write([@used].pack('l'))
            @f.flush
            @positions[key] = @used - 8
          end

          # Yield (key, value, pos). No locking is performed.
          def read_all_values
            @f.seek(8)
            values = []
            while @f.pos < @used
              padded_len = @f.read(4).unpack('l')[0]
              encoded = @f.read(padded_len).unpack("A#{padded_len}")[0]
              value = @f.read(8).unpack('d')[0]
              values << [encoded.strip, value, @f.pos - 8]
            end
            values
          end
        end
      end
    end
  end
end


