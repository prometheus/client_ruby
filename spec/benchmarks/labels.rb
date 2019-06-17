# frozen_string_literal: true

require "benchmark/ips"
require "prometheus/client"
require "prometheus/client/counter"
require "prometheus/client/data_stores/single_threaded"

# Compare the time it takes to observe metrics that have labels (disregarding the actual
# data store)
#
# This benchmark compares 3 different metrics, with 0, 2 and 100 labels respectively,
# and how using `with_values` for some, or all their label values affects performance.
#
# The hypothesis here is that, once labels are introduced, we're validating those labels
# in every observation, but if those labels are "cached" using `with_labels`, we skip that
# validation which should be *considerably* faster.
#
# This completely disregards the storage of this data in memory, and it's highly likely
# that more labels will make things slower in the data store, even if the metrics themselves
# don't add overhead. So the fact that using `with_labels` with all labels adds no overhead
# to the metric itself doesn't mean labels have no overhead.
#
# To see what it looks like with the best-case scenario data store, uncomment the line
# that sets the `data_store` to `SingleThreaded`
#-------------------------------------------------------------------------------------
# Store that doesn't do anything, so we can focus as much as possible on the timings of
# the Metric itself
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

    def all_values; end
  end
end

Prometheus::Client.config.data_store = NoopStore.new # No data storage
# Prometheus::Client.config.data_store = Prometheus::Client::DataStores::SingleThreaded.new # Simple data storage

#-------------------------------------------------------------------------------------
# Set up of the 3 metrics, plus their half-cached and full-cached versions
NO_LABELS_COUNTER = Prometheus::Client::Counter.new(
  :no_labels,
  docstring: "Counter with no labels",
)

TWO_LABELSET = { label1: "a", label2: "b" }
LAST_ONE_LABELSET = { label2: "b" }
TWO_LABELS_COUNTER = Prometheus::Client::Counter.new(
  :two_labels,
  docstring: "Counter with 2 labels",
  labels: %i[label1 label2],
)
TWO_LABELS_ONE_CACHED = TWO_LABELS_COUNTER.with_labels(label1: "a")
TWO_LABELS_ALL_CACHED = TWO_LABELS_COUNTER.with_labels(label1: "a", label2: "b")

HUNDRED_LABELS = (1..100).map { |i| "label#{ i }".to_sym }
HUNDRED_LABELSET = (1..100).map { |i| ["label#{ i }".to_sym, i.to_s] }.to_h
FIRST_FIFTY_LABELSET = (1..50).map { |i| ["label#{ i }".to_sym, i.to_s] }.to_h
LAST_FIFTY_LABELSET = (51..100).map { |i| ["label#{ i }".to_sym, i.to_s] }.to_h

HUNDRED_LABELS_COUNTER = Prometheus::Client::Counter.new(
  :hundred_labels,
  docstring: "Counter with 100 labels",
  labels: HUNDRED_LABELS,
)
HUNDRED_LABELS_HALF_CACHED = HUNDRED_LABELS_COUNTER.with_labels(FIRST_FIFTY_LABELSET)
HUNDRED_LABELS_ALL_CACHED = HUNDRED_LABELS_COUNTER.with_labels(HUNDRED_LABELSET)

#-------------------------------------------------------------------------------------
# Actual Benchmark

Benchmark.ips do |x|
  x.config(:time => 5, :warmup => 2)

  x.report("0 labels") { NO_LABELS_COUNTER.increment }
  x.report("2 labels") { TWO_LABELS_COUNTER.increment(labels: TWO_LABELSET) }
  x.report("100 labels") { HUNDRED_LABELS_COUNTER.increment(labels: HUNDRED_LABELSET) }

  x.report("2 lab, half cached") { TWO_LABELS_ONE_CACHED.increment(labels: LAST_ONE_LABELSET) }
  x.report("100 lab, half cached") { HUNDRED_LABELS_HALF_CACHED.increment(labels: LAST_FIFTY_LABELSET) }

  x.report("2 lab, all cached") { TWO_LABELS_ALL_CACHED.increment }
  x.report("100 lab, all cached") { HUNDRED_LABELS_ALL_CACHED.increment }
end

#-------------------------------------------------------------------------------------
# Conclusion:
#
# Without a data store:
#
#             0 labels      3.592M (± 3.7%) i/s -     18.081M in   5.039832s
#             2 labels    502.898k (± 3.2%) i/s -      2.536M in   5.048618s
#           100 labels     19.467k (± 4.8%) i/s -     98.280k in   5.061444s
#   2 lab, half cached    432.844k (± 3.0%) i/s -      2.180M in   5.041123s
# 100 lab, half cached     20.444k (± 3.4%) i/s -    103.636k in   5.075070s
#    2 lab, all cached      3.668M (± 3.3%) i/s -     18.338M in   5.004442s
#  100 lab, all cached      3.711M (± 4.0%) i/s -     18.544M in   5.005362s
#
# As we expected, labels introduce a significant overhead, even in small numbers, but
# if they are all pre-set, the effect is negligible.
# Pre-setting *some* labels, however, has no performance impact. It may still be desirable
# to avoid repetition, though.
#
# So, if observing measurements in a tight loop, it's highly recommended to use `with_labels`
# and pre-set all labels.
#
#
# With the simplest possible data store:
#
#             0 labels      1.275M (± 3.1%) i/s -      6.419M in   5.038946s
#             2 labels    195.293k (± 4.3%) i/s -    974.600k in   5.000375s
#           100 labels      6.410k (± 7.5%) i/s -     32.022k in   5.028417s
#   2 lab, half cached    187.255k (± 3.5%) i/s -    948.618k in   5.072189s
# 100 lab, half cached      6.846k (± 2.7%) i/s -     34.424k in   5.031776s
#    2 lab, all cached    376.353k (± 3.3%) i/s -      1.890M in   5.025963s
#  100 lab, all cached     11.669k (± 3.0%) i/s -     58.752k in   5.039468s
#
# As mentioned above, once we're storing the data, labels *can* have a serious impact,
# and that impact will be highly store dependent.
