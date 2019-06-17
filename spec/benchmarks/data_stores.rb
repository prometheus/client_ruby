# frozen_string_literal: true

require "benchmark"
require "prometheus/client"
require "prometheus/client/counter"
require "prometheus/client/histogram"
require "prometheus/client/formats/text"
require "prometheus/client/data_stores/single_threaded"
require "prometheus/client/data_stores/synchronized"
require "prometheus/client/data_stores/direct_file_store"

# Compare the time it takes different stores to observe a large number of data points, in
# a multi-threaded environment.
#
# If you create a new store and want to benchmark it, add it to the `STORES` array,
# and run the benchmark to see how it compares to the other options.
#
# Each test instantiates a number of Histograms and Counters, with a random number of
# labels, instantiates a number of threads, and then prepares a a large number of
# observations, which it distributes randomly between the different metrics and threads
# created.
#
# It does this for each of the STORES specified and different THREAD_COUNTS, then once
# all that is ready, it starts the benchmark test and lets the threads run to observe
# those data points.
#
# In addition to timing the observation of data points, the benchmark also runs the Text
# Exporter on the results, and compares them between stores to make sure all stores
# result in the same output being generated. If this output doesn't match exactly,
# something is going wrong, and it probably indicates a bug in the store, so this
# benchmark also acts as a sort of system test for stores. If a mismatch is found, a
# WARNING will show up in the output, and both the expected and actual results will be
# dumped to text files, for help in debugging.
#
# Data generation involves randomness, but the RNG is seeded so that different stores are
# exposed to the same pattern of access (as long as two test cases have the same number
# of threads), reducing the effects on the result of randomness in lock contention.
#
# NOTE: If you leave the default of 1_000_000 DATA_POINTS, then the timing result is
# showing "microseconds per observation", which is the unit we care about.
# We're aiming for 1 microsecond per observation, which is not quite achievable in Ruby,
# but that's what we're trying to approach. If you're trying to compare against this
# goal, set NUM_HISTOGRAMS and MAX_LABELS to 0, for a fair comparison, as both labels
# and histograms are much slower than label-less counters.
#-----------------------------------------------------------------------------------

# Store class that follows the required interface but does nothing. Used as a baseline
# of how much time is spent outside the store.
class NoopStore
  def for_metric(metric_name, metric_type:, metric_settings: {})
    MetricStore.new
  end

  class MetricStore
    def synchronize
      yield
    end

    def set(labels:, val:); end

    def increment(labels:, by: 1); end

    def get(labels:); end

    def all_values; {}; end
  end
end

#-----------------------------------------------------------------------------------

RANDOM_SEED = 12345678
NUM_COUNTERS = 80
NUM_HISTOGRAMS = 20
DATA_POINTS = 1_000_000
MIN_LABELS = 0
MAX_LABELS = 4
THREAD_COUNTS = [1, 2, 4, 8, 12, 16, 20]

TMP_DIR = "/tmp/prometheus_benchmark"

STORES = [
  { store: NoopStore.new },
  { store: Prometheus::Client::DataStores::SingleThreaded.new, max_threads: 1 },
  { store: Prometheus::Client::DataStores::Synchronized.new },
  {
    store: Prometheus::Client::DataStores::DirectFileStore.new(dir: TMP_DIR),
    before: -> () { cleanup_dir(TMP_DIR) },
  }
]

#-----------------------------------------------------------------------------------

class TestSetup
  attr_reader :random, :num_threads, :registry
  attr_reader :metrics, :threads # Simple arrays
  attr_reader :data_points # Hash, indexed by Thread ID, with an array of points to observe
  attr_reader :start_event

  def initialize(store, num_threads)
    Prometheus::Client.config.data_store = @store = store

    @random = Random.new(RANDOM_SEED) # Repeatable random numbers for each test
    @start_event = Concurrent::Event.new # Event all threads wait on to start, once set up
    @num_threads = num_threads
    @threads = []
    @metrics = []
    @data_points = {}
    @registry = Prometheus::Client::Registry.new

    setup_threads
    setup_metrics
    create_datapoints
  end

  def observe!
    start_event.set # Release the threads to process their events
    threads.each { |thr| thr.join } # Wait for all threads to finish and die
  end

  def export!(expected_output)
    output = Prometheus::Client::Formats::Text.marshal(registry)

    # Output validation doesn't work for NoopStore
    return nil if @store.is_a?(NoopStore)

    puts "\nWARNING: Empty output" if !output || output.empty?

    # If this is the first store to run for this number of threads, store expected_output
    return output if expected_output.nil?

    # Otherwise, make sure this store's output was the same as the previous one.
    # If it isn't, there's probably a bug in the store
    return output if output == expected_output

    # Outputs don't match. Report
    expected_filename = "data_mismatch_#{ @store.class.name }_#{ num_threads }thr_expected.txt"
    actual_filename = "data_mismatch_#{ @store.class.name }_#{ num_threads }thr_actual.txt"
    puts "\nWARNING: Output Mismatch.\nSee #{ expected_filename }\nand #{ actual_filename }"

    File.open(expected_filename, "w") { |f| f.write(expected_output) }
    File.open(actual_filename, "w") { |f| f.write(output) }

    return expected_output
  end

  private

  def setup_threads
    latch = Concurrent::CountDownLatch.new(num_threads)

    num_threads.times do |i|
      threads << Thread.new(i) do |thread_id|
        latch.count_down
        start_event.wait # Wait for the test to start
        thread_run(thread_id) # Process this thread's events
      end
    end

    latch.wait # Wait for all threads to have started
  end

  def setup_metrics
    NUM_COUNTERS.times do |i|
      labelset = generate_labelset
      counter =  Prometheus::Client::Counter.new(
        "counter#{ i }".to_sym,
        docstring: "Counter #{ i }",
        labels: labelset.keys,
        preset_labels: labelset,
      )

      metrics << counter
    end

    NUM_HISTOGRAMS.times do |i|
      labelset = generate_labelset
      histogram = Prometheus::Client::Histogram.new(
        "histogram#{ i }".to_sym,
        docstring: "Histogram #{ i }",
        labels: labelset.keys,
        preset_labels: labelset,
      )

      metrics << histogram
    end

    metrics.each { |metric| registry.register(metric) }
  end

  def create_datapoints
    num_threads.times do |i|
      data_points[i] = []
    end

    thread_id = 0
    DATA_POINTS.times do |i|
      thread_id = (thread_id + 1) % num_threads
      metric = random_metric

      if metric.type == :counter
        data_points[thread_id] << [metric]
      else
        data_points[thread_id] << [metric, random.rand * 10]
      end
    end
  end

  def thread_run(thread_id)
    thread_points = data_points[thread_id]
    thread_points.each do |point|
      metric = point[0]
      if metric.type == :counter
        metric.increment
      else
        metric.observe(point[1])
      end
    end
  end

  def generate_labelset
    num_labels = random.rand(MAX_LABELS - MIN_LABELS + 1) + MIN_LABELS
    (1..num_labels).map { |j| ["label#{ j }".to_sym, "foo"] }.to_h
  end

  def random_metric
    metrics[random.rand(metrics.count)]
  end
end

def cleanup_dir(dir)
  Dir.glob("#{ dir }/*").each { |file| File.delete(file) }
end

#-----------------------------------------------------------------------------------

# Monkey-patch the exporter to round Float numbers
# This is necessary in order to compare outputs from different stores, and make sure
# the user-built stores are working correctly.
#
# In multi-threaded scenarios, adding up a large amount of floats in different orders
# results in small rounding errors when adding the same numbers. This is not a bug
# in the store, or anywhere, it's the nature of Floats.
# E.g.: 4909.026018536727
#    vs 4909.026018536722
#
# In the real exporter, this is not a problem, because the exported numbers are still
# correct, but when comparing one to the other, these tiny deltas result in false
# alarms for *all* stores under multiple threads.
#
# Monkey-patching the output line to round the number allows us to compare these outputs
# without any noticeable downside.
module Prometheus
  module Client
    module Formats
      module Text
        def self.metric(name, labels, value)
          sprintf(METRIC_LINE, name, labels, value.round(6))
        end
      end
    end
  end
end

#-----------------------------------------------------------------------------------

Benchmark.bm(45) do |bm|
  THREAD_COUNTS.each do |num_threads|
    expected_exporter_output = nil

    STORES.each do |store_test|
      # Single Threaded stores can't run in multiple threads
      next if store_test[:max_threads] && num_threads > store_test[:max_threads]

      # Cleanup before test
      store_test[:before].call if store_test[:before]

      test_setup = TestSetup.new(store_test[:store], num_threads)
      store_name = store_test[:store].class.name.split("::").last
      test_name = "#{ (store_test[:name] || store_name).ljust(25) } x#{ num_threads }"

      bm.report("Observe #{test_name}") { test_setup.observe! }
      bm.report("Export  #{test_name}") do
        expected_exporter_output = test_setup.export!(expected_exporter_output)
      end
    end

    puts "-" * 80
  end
end

#--------------------------------------------------------------------------------------
# Sample Results:
#
# Only counters, no labels, DirectFileStore stored in TMPFS, Ruby 2.5.1
# ----------------------------------------------------------------
#                                                     user     system      total        real
# Observe NoopStore                 x1            0.390845   0.019915   0.410760 (  0.413240)
# Export  NoopStore                 x1            0.000462   0.000029   0.000491 (  0.000489)
# Observe SingleThreaded            x1            0.946516   0.044122   0.990638 (  0.990801)
# Export  SingleThreaded            x1            0.000837   0.000000   0.000837 (  0.000838)
# Observe Synchronized              x1            4.038891   0.000000   4.038891 (  4.039304)
# Export  Synchronized              x1            0.001227   0.000000   0.001227 (  0.001229)
# Observe DirectFileStore           x1            7.414242   1.732539   9.146781 (  9.147389)
# Export  DirectFileStore           x1            0.009920   0.000243   0.010163 (  0.010170)
# --------------------------------------------------------------------------------
# Observe NoopStore                 x2            0.337919   0.000000   0.337919 (  0.337575)
# Export  NoopStore                 x2            0.000404   0.000000   0.000404 (  0.000379)
# Observe Synchronized              x2            4.313595   0.008714   4.322309 (  4.314901)
# Export  Synchronized              x2            0.001649   0.000155   0.001804 (  0.001809)
# Observe DirectFileStore           x2           22.193105  12.739370  34.932475 ( 21.503215)
# Export  DirectFileStore           x2            0.005982   0.008480   0.014462 (  0.014471)
#
#
#
# Default benchmark (Mix of Counters and Histograms, and up to 4 labels),
# DirectFileStore stored in TMPFS, Ruby 2.5.1
# ------------------------------------------
#                                                     user     system      total        real
# Observe NoopStore                 x1            0.994314   0.027816   1.022130 (  1.025121)
# Export  NoopStore                 x1            0.000537   0.000032   0.000569 (  0.000574)
# Observe SingleThreaded            x1            4.439427   0.027929   4.467356 (  4.470777)
# Export  SingleThreaded            x1            0.006244   0.000000   0.006244 (  0.006250)
# Observe Synchronized              x1            8.292962   0.000000   8.292962 (  8.293737)
# Export  Synchronized              x1            0.006698   0.000000   0.006698 (  0.006706)
# Observe DirectFileStore           x1           13.448161   2.517563  15.965724 ( 15.967281)
# Export  DirectFileStore           x1            0.020115   0.004012   0.024127 (  0.024135)
# --------------------------------------------------------------------------------
# Observe NoopStore                 x2            1.342963   0.020541   1.363504 (  1.354383)
# Export  NoopStore                 x2            0.002923   0.000000   0.002923 (  0.002927)
# Observe Synchronized              x2            8.810914   0.029352   8.840266 (  8.828600)
# Export  Synchronized              x2            0.007535   0.000000   0.007535 (  0.007540)
# Observe DirectFileStore           x2           41.483649  19.362639  60.846288 ( 39.026703)
# Export  DirectFileStore           x2            0.010133   0.013159   0.023292 (  0.023302)
