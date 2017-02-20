# encoding: UTF-8

require "json"
require "mmap"

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

      def get
        @value
      end

      def self.multiprocess
        false
      end
    end

    # A float protected by a mutex backed by a per-process mmaped file.
    class MmapedValue
      @@files = {}
      @@files_lock = Mutex.new
      @@pid = Process.pid

      def initialize(type, metric_name, name, labels, multiprocess_mode='')
        @@pid = Process.pid
        file_prefix = type.to_s
        if type == :gauge
          file_prefix += '_' +  multiprocess_mode.to_s
        end

        @@files_lock.synchronize do
          if !@@files.has_key?(file_prefix)
            filename = File.join(ENV['prometheus_multiproc_dir'], "#{file_prefix}_#{@@pid}.db")
            @@files[file_prefix] = MmapedDict.new(filename)
          end
        end

        @file = @@files[file_prefix]
        labelnames = []
        labelvalues = []
        labels.each do |k, v|
          labelnames << k
          labelvalues << v
        end

        @key = [metric_name, name, labelnames, labelvalues].to_json
        @value = @file.read_value(@key)
        @mutex = Mutex.new
      end

      def increment(amount=1)
        @mutex.synchronize do
          @value += amount
          @file.write_value(@key, @value)
        end
      end

      def set(value)
        @mutex.synchronize do
          @value = value
          @file.write_value(@key, @value)
        end
      end

      def get
        @mutex.synchronize do
          return @value
        end
      end

      def self.multiprocess
        true
      end
    end

    # Should we enable multi-process mode?
    # This needs to be chosen before the first metric is constructed,
    # and as that may be in some arbitrary library the user/admin has
    # no control over we use an enviroment variable.
    if ENV.has_key?('prometheus_multiproc_dir')
      ValueClass = MmapedValue
    else
      ValueClass = SimpleValue
    end
  end
end

# A dict of doubles, backed by an mmapped file.
#
# The file starts with a 4 byte int, indicating how much of it is used.
# Then 4 bytes of padding.
# There's then a number of entries, consisting of a 4 byte int which is the
# size of the next field, a utf-8 encoded string key, padding to an 8 byte
# alignment, and then a 8 byte float which is the value.
#
# TODO(julius): dealing with Mmap.new, truncate etc. errors?
class MmapedDict
  @@INITIAL_MMAP_SIZE = 1024*1024

  attr_reader :m, :capacity, :used, :positions

  def initialize(filename)
    @mutex = Mutex.new
    @f = File.open(filename, 'a+b')
    if @f.size == 0
      @f.truncate(@@INITIAL_MMAP_SIZE)
    end
    @capacity = @f.size
    @m = Mmap.new(filename, 'rw', Mmap::MAP_SHARED)
    # @m.mlock # TODO: Why does this raise an error?

    @positions = {}
    @used = @m[0..3].unpack('l')[0]
    if @used == 0
      @used = 8
      @m[0..3] = [@used].pack('l')
    else
      read_all_values.each do |key, _, pos|
        @positions[key] = pos
      end
    end
  end

  # Yield (key, value, pos). No locking is performed.
  def all_values
    read_all_values.map { |k, v, p| [k, v] }
  end

  def read_value(key)
    @mutex.synchronize do
      if !@positions.has_key?(key)
        init_value(key)
      end
    end
    pos = @positions[key]
    # We assume that reading from an 8 byte aligned value is atomic.
    @m[pos..pos+7].unpack('d')[0]
  end

  def write_value(key, value)
    @mutex.synchronize do
      if !@positions.has_key?(key)
        init_value(key)
      end
    end
    pos = @positions[key]
    # We assume that writing to an 8 byte aligned value is atomic.
    @m[pos..pos+7] = [value].pack('d')
  end

  def close()
    @m.munmap
    @f.close
  end

  private

  # Initialize a value. Lock must be held by caller.
  def init_value(key)
    # Pad to be 8-byte aligned.
    padded = key + (' ' * (8 - (key.length + 4) % 8))
    value = [key.length, padded, 0.0].pack("lA#{padded.length}d")
    while @used + value.length > @capacity
      @capacity *= 2
      @f.truncate(@capacity)
      @m = Mmap.new(@f.path, 'rw', Mmap::MAP_SHARED)
    end
    @m[@used..@used + value.length] = value

    # Update how much space we've used.
    @used += value.length
    @m[0..3] = [@used].pack('l')
    @positions[key] = @used - 8
  end

  # Yield (key, value, pos). No locking is performed.
  def read_all_values
    pos = 8
    values = []
    while pos < @used
      encoded_len = @m[pos..-1].unpack('l')[0]
      pos += 4
      encoded = @m[pos..-1].unpack("A#{encoded_len}")[0]
      padded_len = encoded_len + (8 - (encoded_len + 4) % 8)
      pos += padded_len
      value = @m[pos..-1].unpack('d')[0]
      values << [encoded, value, pos]
      pos += 8
    end
    values
  end
end