# frozen_string_literal: true

require 'benchmark'
require 'benchmark/ips'
require 'vernier'

require 'prometheus/client'
require 'prometheus/client/data_stores/single_threaded'
require 'prometheus/client/histogram'
require 'prometheus/client/histogram_fixed'

# NoopStore doesn't work here, because it doesn't implement `get` and `all_values` methods
Prometheus::Client.config.data_store = Prometheus::Client::DataStores::SingleThreaded.new # Simple data storage

BUCKETS = [
  0.00001, 0.000015, 0.00002, 0.000025, 0.00003, 0.000035, 0.00004, 0.000045, 0.00005, 0.000055, 0.00006, 0.000065, 0.00007, 0.000075, 0.00008, 0.000085,
  0.00009, 0.000095, 0.0001, 0.000101, 0.000102, 0.000103, 0.000104, 0.000105, 0.000106, 0.000107, 0.000108, 0.000109, 0.00011, 0.000111, 0.000112, 0.000113,
  0.000114, 0.000115, 0.000116, 0.000117, 0.000118, 0.000119, 0.00012, 0.000121, 0.000122, 0.000123, 0.000124, 0.000125, 0.000126, 0.000127, 0.000128,
  0.000129, 0.00013, 0.000131, 0.000132, 0.000133, 0.000134, 0.000135, 0.000136, 0.000137, 0.000138, 0.000139, 0.00014, 0.000141, 0.000142, 0.000143, 0.000144,
  0.000145, 0.000146, 0.000147, 0.000148, 0.000149, 0.00015, 0.000151, 0.000152, 0.000153, 0.000154, 0.000155, 0.000156, 0.000157, 0.000158, 0.000159, 0.00016,
  0.000161, 0.000162, 0.000163, 0.000164, 0.000165, 0.000166, 0.000167, 0.000168, 0.000169, 0.00017, 0.000171, 0.000172, 0.000173, 0.000174, 0.000175,
  0.000176, 0.000177, 0.000178, 0.000179, 0.00018, 0.000181, 0.000182, 0.000183, 0.000184, 0.000185, 0.000186, 0.000187, 0.000188, 0.000189, 0.00019, 0.000191,
  0.000192, 0.000193, 0.000194, 0.000195, 0.000196, 0.000197, 0.000198, 0.000199, 0.0002, 0.00021, 0.00022, 0.00023, 0.00024, 0.00025, 0.00026,
  0.00027, 0.00028, 0.00029, 0.0003, 0.00031, 0.00032, 0.00033, 0.00034, 0.00035, 0.00036, 0.00037, 0.00038, 0.00039, 0.0004, 0.00041, 0.00042,
  0.00043, 0.00044, 0.00045, 0.00046, 0.00047, 0.00048, 0.00049, 0.0005, 0.00051, 0.00052, 0.00053, 0.00054, 0.00055, 0.00056, 0.00057, 0.00058,
  0.00059, 0.0006, 0.00061, 0.00062, 0.00063, 0.00064, 0.00065, 0.00066, 0.00067, 0.00068, 0.00069, 0.0007, 0.00071, 0.00072, 0.00073, 0.00074,
  0.00075, 0.00076, 0.00077, 0.00078, 0.00079, 0.0008, 0.00081, 0.00082, 0.00083, 0.00084, 0.00085, 0.00086, 0.00087, 0.00088, 0.00089, 0.0009,
  0.00091, 0.00092, 0.00093, 0.00094, 0.00095, 0.00096, 0.00097, 0.00098, 0.00099, 0.001, 0.0015, 0.002, 0.0025, 0.003, 0.0035, 0.004, 0.0045, 0.005,
  0.0055, 0.006, 0.0065, 0.007, 0.0075, 0.008, 0.0085, 0.009, 0.0095, 0.01, 0.015, 0.02, 0.025, 0.03, 0.035, 0.04, 0.045, 0.05, 0.055, 0.06, 0.065, 0.07,
  0.075, 0.08, 0.085, 0.09, 0.095, 0.1, 0.15, 0.2, 0.25, 0.3, 0.35, 0.4, 0.45, 0.5, 0.55, 0.6, 0.65, 0.7, 0.75, 0.8, 0.85, 0.9, 0.95, 1.0, 1.5, 2.0, 2.5,
  3.0, 3.5, 4.0, 4.5, 5.0, 5.5, 6.0, 6.5, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0, 10.5, 11.0, 11.5, 12.0, 12.5, 13.0, 13.5, 14.0, 14.5, 15.0, 15.5, 16.0, 16.5, 17.0, 17.5
].freeze

def allocations
  x = GC.stat(:total_allocated_objects)
  yield
  GC.stat(:total_allocated_objects) - x
end

# Setup 4 test cases
# 1. Default buckets + no labels
# 2. Large buckets + no labels
# 3. Default buckets + 2 labels
# 4. Large buckets + 2 labels
TEST_CASES = {
  'default buckets + no lables' => [
    Prometheus::Client::Histogram.new(
      :default_buckets_old,
      docstring: 'default buckets + no lables'
    ),
    Prometheus::Client::HistogramFixed.new(
      :default_buckets_new,
      docstring: 'default buckets + no lables'
    )
  ],
  'large buckets + no lables' => [
    Prometheus::Client::Histogram.new(
      :large_buckets_old,
      docstring: 'large buckets + no lables',
      buckets: BUCKETS
    ),
    Prometheus::Client::HistogramFixed.new(
      :large_buckets_new,
      docstring: 'large buckets + no lables',
      buckets: BUCKETS
    )
  ],
  'default buckets + labels' => [
    Prometheus::Client::Histogram.new(
      :default_buckets_with_labels_old,
      docstring: 'default buckets + labels',
      labels: [:label1, :label2]
    ),
    Prometheus::Client::HistogramFixed.new(
      :default_buckets_with_labels_new,
      docstring: 'default buckets + labels',
      labels: [:label1, :label2]
    )
  ],
  'large buckets + labels' => [
    Prometheus::Client::Histogram.new(
      :large_buckets_with_labels_old,
      docstring: 'large buckets + labels',
      buckets: BUCKETS,
      labels: [:label1, :label2]
    ),
    Prometheus::Client::HistogramFixed.new(
      :large_buckets_with_labels_new,
      docstring: 'large buckets + labels',
      buckets: BUCKETS,
      labels: [:label1, :label2]
    )
  ],
}.freeze

labels = [1,2,3,4,5,6,7,8,9]

TEST_CASES.each do |name, (old, new)|
  with_labels = name.include?('+ labels')
  Benchmark.ips do |bm|
    bm.report("#{name} -> Observe old") do
      if with_labels
        old.observe(rand(BUCKETS.last + 10), labels: { label1: labels.sample, label2: labels.sample })
      else
        old.observe(rand(BUCKETS.last + 10))
      end
    end
    bm.report("#{name} -> Observe new") do
      if with_labels
        new.observe(rand(BUCKETS.last + 10), labels: { label1: labels.sample, label2: labels.sample })
      else
        new.observe(rand(BUCKETS.last + 10))
      end
    end

    bm.compare!
  end

  Benchmark.ips do |bm|
    bm.report("#{name} -> Values old") { old.values }
    bm.report("#{name} -> Values new") { new.values }

    bm.compare!
  end
end

# Sample usage of profiler
val = rand(BUCKETS.last)
l = { label1: 1, label2: 2 }

# Vernier.profile(mode: :wall, out: 'x.json', interval: 1, allocation_interval: 1) do
#   100000.times { large_buckets_new.observe(val, labels: l) }
# end

old, new = TEST_CASES['large buckets + labels']

puts "Old#observe allocations -> #{allocations { 1000.times { old.observe(val, labels: l) }}}"
puts "New#observe allocations -> #{allocations { 1000.times { new.observe(val, labels: l) }}}"

puts "Old#values allocations -> #{allocations { 1000.times { old.values }}}"
puts "New#values allocations -> #{allocations { 1000.times { new.values }}}"


# Results:
# 1. Default buckets + no labels
# #observe is almost the same, but #values is 2.15x faster
#
# default buckets + no lables -> Observe new:   492718.9 i/s
# default buckets + no lables -> Observe old:   475856.7 i/s - same-ish: difference falls within error
# default buckets + no lables -> Values new:    98723.1 i/s
# default buckets + no lables -> Values old:    45867.1 i/s - 2.15x  slower
#
# 2. Large buckets + no labels
# #observe is almost the same, but #values is 2.93x faster
#
# large buckets + no lables -> Observe new:   441325.9 i/s
# large buckets + no lables -> Observe old:   437752.4 i/s - same-ish: difference falls within error
# large buckets + no lables -> Values new:     4792.0 i/s
# large buckets + no lables -> Values old:     1636.8 i/s - 2.93x  slower
#
# 3. Default buckets + 2 labels
# #observe is 1.44x faster, #values is 2.70x faster
#
# default buckets + labels -> Observe new:   450357.3 i/s
# default buckets + labels -> Observe old:   311747.3 i/s - 1.44x  slower
# default buckets + labels -> Values new:     1633.8 i/s
# default buckets + labels -> Values old:      604.2 i/s - 2.70x  slower
#
# 4. Large buckets + 2 labels
# #observe is 1.41x faster, #values is 9.57x faster
#
# large buckets + labels -> Observe new:   392597.2 i/s
# large buckets + labels -> Observe old:   277499.9 i/s - 1.41x  slower
# large buckets + labels -> Values new:      247.6 i/s
# large buckets + labels -> Values old:       25.9 i/s - 9.57x  slower
#
# 5. Allocations for 1000 observations for #observe method
# Old allocations -> 11001 - 11 allocations per observation
# New allocations -> 1000  - 1  allocation per observation
# Last place left `bucket_label_set = base_label_set.dup` in #observe method
#
# 6. Allocations for 1000 observations for #values method
# Old#values allocations -> 96150000
# New#values allocations -> 3325000
# almost 30x less allocations
