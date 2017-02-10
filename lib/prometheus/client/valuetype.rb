# encoding: UTF-8

module Prometheus
  module Client
    class SimpleValue
      def initialize(type, metric_name, name, labels, value = 0)
        @value = value
      end

      def set(value)
        @value = value
      end

      def increment(by = 1)
        @value += by
      end

      def get()
        @value
      end
    end

    def MultiProcessValue(pid=Process.pid)
      files = {}
      files_lock = Mutex.new

      # A float protected by a mutex backed by a per-process mmaped file.
      class MmapedValue
        def initialize(type, metric_name, name, labels, multiprocess_mode='')
          file_prefix = typ
          if type == :gauge
            file_prefix += '_' +  multiprocess_mode
          end

          files_lock.synchronize do
            if files.has_key?(file_prefix)
              filename = File.join(ENV['prometheus_multiproc_dir'], "#{file_prefix}_#{pid}.db")
              files[file_prefix] = MmapedDict.new(filename)
            end
          end

          @file = files[file_prefix]
          labelnames = []
          labelvalues = []
          labels.each do |k, v|
            labelnames << k
            labelvalues << v
          end

          @key = [metric_name, name, labelnames, labelvalues)].to_json
          @value = @file.read_value(@key)
          @mutex = Mutex.new
        end

        def inc(self, amount):
          @mutex.synchronize do
            self._value += amount
            self._file.write_value(self._key, self._value)
          end
        end

        def set(self, value):
          @mutex.synchronize do
            self._value = value
            self._file.write_value(self._key, self._value)
          end
        end

        def get(self):
          @mutex.synchronize do
            return self._value
          end
        end

        def multiprocess
          true
        end
      end

      return MmapedValue
    end

    ValueType = SimpleValue
  end
end

# A dict of doubles, backed by an mmapped file.
#
# The file starts with a 4 byte int, indicating how much of it is used.
# Then 4 bytes of padding.
# There's then a number of entries, consisting of a 4 byte int which is the
# size of the next field, a utf-8 encoded string key, padding to a 8 byte
#alignment, and then a 8 byte float which is the value.
#
# TODO(julius): do Mmap.new, truncate, etc., raise exceptions on failure?
class MmapedDict(object):
  @@_INITIAL_MMAP_SIZE = 1024*1024

  def initialize(filename):
    @mutex = Mutex.new
    @m = Mmap.new(filename)
    if @m.empty?
      @m.extend(@@INITIAL_MMAP_SIZE)
    end
    @capacity = @m.size
    @m.mlock

    @positions = {}
    @used = @m.unpack('l')[0]
    if @used == 0:
      @used = 8
      @m[0..3] = [@used].pack('l')
    else
      read_all_values.each do |key, _, pos|
        @positions[key] = pos
      end
    end

  private
  # Initialize a value. Lock must be held by caller.
  def init_value(self, key):
    encoded = key.encode('utf-8')
    # Pad to be 8-byte aligned.
    padded = encoded + (b' ' * (8 - (encoded.length + 4) % 8))
    value = [encoded.length, padded, 0.0].pack('lA#{padded.length}d')
    while @used + value.length > @capacity:
      @m.extend(@capacity)
      @capacity *= 2
      ####@m = mmap.mmap(self._f.fileno(), self._capacity)
    @m[@used:@used + value.length] = value

    # Update how much space we've used.
    @used += value.length
    @m[0..3] = [@used].pack('l')
    @positions[key] = @used - 8

  # Yield (key, value, pos). No locking is performed.
  def read_all_values(self):
    pos = 8
    values = []
    while pos < @used:
      encoded_len = @m[pos..-1].unpack('l')[0]
      pos += 4
      encoded = @m[pos..-1].unpack('A#{encoded_len}')[0]
      padded_len = encoded_len + (8 - (encoded_len + 4) % 8)
      pos += padded_len
      value = @m[pos..-1].unpack('d')[0]
      values << encoded.decode('utf-8'), value, pos
      pos += 8
    end
    values
  end

  # Yield (key, value, pos). No locking is performed.
  def all_values():
    read_all_values.map { |k, v, p| [k, v] }

  def read_value(key):
    @mutex.synchronize do
      if !@positions.has_key?(key)
        init_value(key)
      end
    end
    pos = @positions[key]
    # We assume that reading from an 8 byte aligned value is atomic.
    @m[pos..-1].unpack('d')[0]

  def write_value(key, value):
    @mutex.synchronize do
      if !@positions.has_key?(key)
        init_value(key)
      end
    end
    pos = @positions[key]
    # We assume that writing to an 8 byte aligned value is atomic.
    @m[pos..-1] = [value].pack('d')

  def close():
    @m.munmap