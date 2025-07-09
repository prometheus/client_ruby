require 'fileutils'
require "cgi"

module Prometheus
  module Client
    module DataStores
      # Stores data in binary files, one file per process.
      # This is generally the recommended store to use to deal with pre-fork servers and
      # other "multi-process" scenarios.
      #
      # Each process will get a file for all its metrics, and it will manage its contents by
      # storing keys next to binary-encoded Floats, and keeping track of the offsets of
      # those Floats, to be able to update them directly as they increase.
      #
      # When exporting metrics, the process that gets scraped by Prometheus  will find
      # all the files for all processes, read their contents, and aggregate them
      # (generally that means SUMming the values for each labelset).
      #
      # In order to do this, each Metric needs an `:aggregation` setting, specifying how
      # to aggregate the multiple possible values we can get for each labelset. By default,
      # Counters, Histograms and Summaries get `SUM`med, and Gauges will report `ALL`
      # values, tagging each one with a `pid` label.
      # For Gauges, it's also possible to set `SUM`, MAX` or `MIN` as aggregation, to get
      # the highest / lowest value / or the sum of all the processes / threads.
      #
      # Before using this Store, please read the "`DirectFileStore` caveats and things to
      # keep in mind" section of the main README in this repository. It includes a number
      # of important things to keep in mind.

      class DirectFileStore
        class InvalidStoreSettingsError < StandardError; end
        AGGREGATION_MODES = [MAX = :max, MIN = :min, SUM = :sum, ALL = :all, MOST_RECENT = :most_recent]
        DEFAULT_METRIC_SETTINGS = { aggregation: SUM }
        DEFAULT_GAUGE_SETTINGS = { aggregation: ALL }

        def initialize(dir:)
          @store_settings = { dir: dir }
          @store_opened_by_pid = nil
          @lock = Monitor.new

          FileUtils.mkdir_p(dir)
        end

        def for_metric(metric_name, metric_type:, metric_settings: {})
          default_settings = DEFAULT_METRIC_SETTINGS
          if metric_type == :gauge
            default_settings = DEFAULT_GAUGE_SETTINGS
          end

          settings = default_settings.merge(metric_settings)
          validate_metric_settings(metric_type, settings)

          MetricStore.new(metric_name: metric_name,
                          metric_settings: settings,
                          store: self)
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

        def in_process_sync
          @lock.synchronize { yield }
        end

        def internal_store
          if @store_opened_by_pid != process_id
            @store_opened_by_pid = process_id
            @internal_store = FileMappedDict.new(filemap_filename)
          else
            @internal_store
          end
        end

        def process_id
          Process.pid
        end

        # Filename for this metric's PStore (one per process)
        def filemap_filename
          filename = "metrics___#{ process_id }.bin"
          File.join(@store_settings[:dir], filename)
        end

        def all_store_files
          Dir.glob(File.join(@store_settings[:dir], "metrics___*"))
        end

        # Returns all the values for all metrics in all stored files, without any aggregation
        # Optionally filtered down to only one metric name
        # TODO: Document the returned "shape"
        def all_raw_metrics_values(only_metric_name: nil)
          stores_data = Hash.new{ |hash, key| hash[key] = [] }

          # There's no need to call `synchronize` here. We're opening a second handle to
          # the file, and `flock`ing it, which prevents inconsistent reads
          all_store_files.each do |file_path|
            begin
              store = FileMappedDict.new(file_path, true)
              store.all_values.each do |(labelset_qs, v, ts)|
                # Labels come as a query string, and CGI::parse returns arrays for each key
                # "foo=bar&x=y" => { "foo" => ["bar"], "x" => ["y"] }
                # Turn the keys back into symbols, and remove the arrays
                label_set = CGI::parse(labelset_qs).map do |k, vs|
                  [k.to_sym, vs.first]
                end.to_h

                unless only_metric_name && only_metric_name != label_set[:___metric_name]
                  stores_data[label_set] << [v, ts]
                end
              end
            ensure
              store.close if store
            end
          end

          stores_data
        end

        private

        def validate_metric_settings(metric_type, metric_settings)
          unless metric_settings.has_key?(:aggregation) &&
            AGGREGATION_MODES.include?(metric_settings[:aggregation])
            raise InvalidStoreSettingsError,
                  "Metrics need a valid :aggregation key"
          end

          unless (metric_settings.keys - [:aggregation]).empty?
            raise InvalidStoreSettingsError,
                  "Only :aggregation setting can be specified"
          end

          if metric_settings[:aggregation] == MOST_RECENT && metric_type != :gauge
            raise InvalidStoreSettingsError,
                  "Only :gauge metrics support :most_recent aggregation"
          end
        end

        class MetricStore
          attr_reader :metric_name, :store, :values_aggregation_mode

          def initialize(metric_name:, metric_settings:, store:)
            @metric_name = metric_name
            @values_aggregation_mode = metric_settings[:aggregation]
            @store = store
          end

          # see DirectFileStore#synchronize for when to use this method
          def synchronize(&block)
            store.synchronize(&block)
          end

          def set(labels:, val:)
            store.in_process_sync do
              store.internal_store.write_value(store_key(labels), val.to_f)
            end
          end

          def increment(labels:, by: 1)
            if @values_aggregation_mode == DirectFileStore::MOST_RECENT
              raise InvalidStoreSettingsError,
                    "The :most_recent aggregation does not support the use of increment"\
                      "/decrement"
            end

            key = store_key(labels)
            store.in_process_sync do
              store.internal_store.increment_value(key, by.to_f)
            end
          end

          def get(labels:)
            store.in_process_sync do
              store.internal_store.read_value(store_key(labels))
            end
          end

          def all_values
            all_metrics_values = store.all_raw_metrics_values(only_metric_name: metric_name.to_s)

            # Aggregate all the different values for each label_set
            aggregate_hash = Hash.new { |hash, key| hash[key] = 0.0 }
            all_metrics_values.each_with_object(aggregate_hash) do |(label_set, values), acc|
              acc[label_set.except(:___metric_name)] = aggregate_values(values)
            end
          end

          private

          def store_key(labels)
            # Maybe we don't need to do this, but it seems like we would?
            # Why have we been getting away with not doing this?
            # Maybe remove this and hammer test for corruption?
            # I think `stringify_values` in `metric.rb` does the dup'ing we need, but it seems to me
            # that if @all_labels_preset, then we are modifying those preset labels...
            # maybe we should `return preset_labels.dup` in `metric.rb#label_set_for`, which would
            # hurt performance for those presets, but would make it better for the rest, which is the
            # majority.
            labels = labels.dup

            labels[:___metric_name] = metric_name

            if @values_aggregation_mode == ALL
              labels[:pid] = store.process_id
            end

            labels.to_a.sort.map{|k,v| "#{CGI::escape(k.to_s)}=#{CGI::escape(v.to_s)}"}.join('&')
          end

          def aggregate_values(values)
            ValuesAggregator.aggregate_values(values, @values_aggregation_mode)
          end
        end

        private_constant :MetricStore

        class ValuesAggregator
          def self.aggregate_values(values, aggregation_mode)
            # Each entry in the `values` array is a tuple of `value` and `timestamp`,
            # so for all aggregations except `MOST_RECENT`, we need to only take the
            # first value in each entry and ignore the second.
            if aggregation_mode == MOST_RECENT
              latest_tuple = values.max { |a,b| a[1] <=> b[1] }
              latest_tuple.first # return the value without the timestamp
            else
              values = values.map(&:first) # Discard timestamps

              if aggregation_mode == SUM
                values.inject { |sum, element| sum + element }
              elsif aggregation_mode == MAX
                values.max
              elsif aggregation_mode == MIN
                values.min
              elsif aggregation_mode == ALL
                values.first
              else
                raise InvalidStoreSettingsError,
                      "Invalid Aggregation Mode: #{ aggregation_mode }"
              end
            end
          end
        end

        # A dict of doubles, backed by an file we access directly as a byte array.
        #
        # The file starts with a 4 byte int, indicating how much of it is used.
        # Then 4 bytes of padding.
        # There's then a number of entries, consisting of a 4 byte int which is the
        # size of the next field, a utf-8 encoded string key, padding to an 8 byte
        # alignment, and then a 8 byte float which is the value, and then a 8 byte
        # float which is the unix timestamp when the value was set.
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
              with_file_lock { populate_positions }
            else
              # File is empty. Init the `used` counter, if we're in write mode
              if !readonly
                @used = 8
                @f.seek(0)
                @f.write([@used].pack('l'))
              end
            end
          end

          # Return a list of key-value pairs
          def all_values
            with_file_lock do
              @positions.map do |key, pos|
                @f.seek(pos)
                value, timestamp = @f.read(16).unpack('dd')
                [key, value, timestamp]
              end
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

            now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            pos = @positions[key]
            @f.seek(pos)
            @f.write([value, now].pack('dd'))
            @f.flush
          end

          def increment_value(key, by)
            if !@positions.has_key?(key)
              init_value(key)
            end

            pos = @positions[key]
            @f.seek(pos)
            value = @f.read(8).unpack('d')[0]

            now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            @f.seek(-8, :CUR)
            @f.write([value + by, now].pack('dd'))
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
            value = [padded.length, padded, 0.0, 0.0].pack("lA#{padded.length}dd")
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
            @positions[key] = @used - 16
          end

          # Read position of all keys. No locking is performed.
          def populate_positions
            @f.seek(8)
            while @f.pos < @used
              padded_len = @f.read(4).unpack('l')[0]
              key = @f.read(padded_len).unpack("A#{padded_len}")[0].strip
              @positions[key] = @f.pos
              @f.seek(16, :CUR)
            end
          end
        end
      end
    end
  end
end
