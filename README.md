# Prometheus Ruby Client

A suite of instrumentation metric primitives for Ruby that can be exposed
through a HTTP interface. Intended to be used together with a
[Prometheus server][1].

[![Gem Version][4]](http://badge.fury.io/rb/prometheus-client)
[![Build Status][3]](http://travis-ci.org/prometheus/client_ruby)
[![Coverage Status][7]](https://coveralls.io/r/prometheus/client_ruby)

## Usage

### Overview

```ruby
require 'prometheus/client'

# returns a default registry
prometheus = Prometheus::Client.registry

# create a new counter metric
http_requests = Prometheus::Client::Counter.new(:http_requests, docstring: 'A counter of HTTP requests made')
# register the metric
prometheus.register(http_requests)

# equivalent helper function
http_requests = prometheus.counter(:http_requests, docstring: 'A counter of HTTP requests made')

# start using the counter
http_requests.increment
```

### Rack middleware

There are two [Rack][2] middlewares available, one to expose a metrics HTTP
endpoint to be scraped by a Prometheus server ([Exporter][9]) and one to trace all HTTP
requests ([Collector][10]).

It's highly recommended to enable gzip compression for the metrics endpoint,
for example by including the `Rack::Deflater` middleware.

```ruby
# config.ru

require 'rack'
require 'prometheus/middleware/collector'
require 'prometheus/middleware/exporter'

use Rack::Deflater
use Prometheus::Middleware::Collector
use Prometheus::Middleware::Exporter

run ->(_) { [200, {'Content-Type' => 'text/html'}, ['OK']] }
```

Start the server and have a look at the metrics endpoint:
[http://localhost:5000/metrics](http://localhost:5000/metrics).

For further instructions and other scripts to get started, have a look at the
integrated [example application](examples/rack/README.md).

### Pushgateway

The Ruby client can also be used to push its collected metrics to a
[Pushgateway][8]. This comes in handy with batch jobs or in other scenarios
where it's not possible or feasible to let a Prometheus server scrape a Ruby
process. TLS and basic access authentication are supported.

**Attention**: The implementation still uses the legacy API of the pushgateway.

```ruby
require 'prometheus/client'
require 'prometheus/client/push'

registry = Prometheus::Client.registry
# ... register some metrics, set/increment/observe/etc. their values

# push the registry state to the default gateway
Prometheus::Client::Push.new('my-batch-job').add(registry)

# optional: specify the instance name (instead of IP) and gateway.
Prometheus::Client::Push.new('my-batch-job', 'foobar', 'https://example.domain:1234').add(registry)

# If you want to replace any previously pushed metrics for a given instance,
# use the #replace method.
Prometheus::Client::Push.new('my-batch-job').replace(registry)

# If you want to delete all previously pushed metrics for a given instance,
# use the #delete method.
Prometheus::Client::Push.new('my-batch-job').delete
```

## Metrics

The following metric types are currently supported.

### Counter

Counter is a metric that exposes merely a sum or tally of things.

```ruby
counter = Prometheus::Client::Counter.new(:service_requests_total, docstring: '...', labels: [:service])

# increment the counter for a given label set
counter.increment(labels: { service: 'foo' })

# increment by a given value
counter.increment(by: 5, labels: { service: 'bar' })

# get current value for a given label set
counter.get(labels: { service: 'bar' })
# => 5
```

### Gauge

Gauge is a metric that exposes merely an instantaneous value or some snapshot
thereof.

```ruby
gauge = Prometheus::Client::Gauge.new(:room_temperature_celsius, docstring: '...', labels: [:room])

# set a value
gauge.set(21.534, labels: { room: 'kitchen' })

# retrieve the current value for a given label set
gauge.get(labels: { room: 'kitchen' })
# => 21.534

# increment the value (default is 1)
gauge.increment(labels: { room: 'kitchen' })
# => 22.534

# decrement the value by a given value
gauge.decrement(by: 5, labels: { room: 'kitchen' })
# => 17.534
```

### Histogram

A histogram samples observations (usually things like request durations or
response sizes) and counts them in configurable buckets. It also provides a sum
of all observed values.

```ruby
histogram = Prometheus::Client::Histogram.new(:service_latency_seconds, docstring: '...', labels: [:service])

# record a value
histogram.observe(Benchmark.realtime { service.call(arg) }, labels: { service: 'users' })

# retrieve the current bucket values
histogram.get(labels: { service: 'users' })
# => { 0.005 => 3, 0.01 => 15, 0.025 => 18, ..., 2.5 => 42, 5 => 42, 10 = >42 }
```

### Summary

Summary, similar to histograms, is an accumulator for samples. It captures
Numeric data and provides an efficient percentile calculation mechanism.

For now, only `sum` and `total` (count of observations) are supported, no actual quantiles.

```ruby
summary = Prometheus::Client::Summary.new(:service_latency_seconds, docstring: '...', labels: [:service])

# record a value
summary.observe(Benchmark.realtime { service.call() }, labels: { service: 'database' })

# retrieve the current sum and total values
summary_value = summary.get(labels: { service: 'database' })
summary_value.sum # => 123.45
summary_value.count # => 100
```

## Labels

All metrics can have labels, allowing grouping of related time series.

Labels are an extremely powerful feature, but one that must be used with care.
Refer to the best practices on [naming](https://prometheus.io/docs/practices/naming/) and 
[labels](https://prometheus.io/docs/practices/instrumentation/#use-labels).

Most importantly, avoid labels that can have a large number of possible values (high 
cardinality). For example, an HTTP Status Code is a good label. A User ID is **not**.

Labels are specified optionally when updating metrics, as a hash of `label_name => value`.
Refer to [the Prometheus documentation](https://prometheus.io/docs/concepts/data_model/#metric-names-and-labels) 
as to what's a valid `label_name`.

In order for a metric to accept labels, their names must be specified when first initializing 
the metric. Then, when the metric is updated, all the specified labels must be present.

Example:

```ruby
https_requests_total = Counter.new(:http_requests_total, docstring: '...', labels: [:service, :status_code])

# increment the counter for a given label set
https_requests_total.increment(labels: { service: "my_service", status_code: response.status_code })
```

### Pre-set Label Values

You can also "pre-set" some of these label values, if they'll always be the same, so you don't
need to specify them every time:

```ruby
https_requests_total = Counter.new(:http_requests_total, 
                                   docstring: '...', 
                                   labels: [:service, :status_code],
                                   preset_labels: { service: "my_service" })

# increment the counter for a given label set
https_requests_total.increment(labels: { status_code: response.status_code })
```

### `with_labels`

Similar to pre-setting labels, you can get a new instance of an existing metric object,
with a subset (or full set) of labels set, so that you can increment / observe the metric
without having to specify the labels for every call.

Moreover, if all the labels the metric can take have been pre-set, validation of the labels
is done on the call to `with_labels`, and then skipped for each observation, which can 
lead to performance improvements. If you are incrementing a counter in a fast loop, you
definitely want to be doing this.


Examples:

**Pre-setting labels for ease of use:**

```ruby
# in the metric definition:
records_processed_total = registry.counter.new(:records_processed_total, 
                                               docstring: '...', 
                                               labels: [:service, :component],
                                               preset_labels: { service: "my_service" })

# in one-off calls, you'd specify the missing labels (component in this case)
records_processed_total.increment(labels: { component: 'a_component' })

# you can also have a "view" on this metric for a specific component where this label is
# pre-set:
class MyComponent
  def metric
    @metric ||= records_processed_total.with_labels(component: "my_component")
  end
  
  def process
    records.each do |record|
      # process the record
      metric.increment 
    end
  end
end
```


## Data Stores

The data for all the metrics (the internal counters associated with each labelset) 
is stored in a global Data Store object, rather than in the metric objects themselves.
(This "storage" is ephemeral, generally in-memory, it's not "long-term storage")

The main reason to do this is that different applications may have different requirements
for their metrics storage. Application running in pre-fork servers (like Unicorn, for
example), require a shared store between all the processes, to be able to report coherent
numbers. At the same time, other applications may not have this requirement but be very
sensitive to performance, and would prefer instead a simpler, faster store.

By having a standardized and simple interface that metrics use to access this store, 
we abstract away the details of storing the data from the specific needs of each metric.
This allows us to then simply swap around the stores based on the needs of different 
applications, with no changes to the rest of the client. 

The client provides 3 built-in stores, but if neither of these is ideal for your 
requirements, you can easily make your own store and use that instead. More on this below.

### Configuring which store to use.

By default, the Client uses the `Synchronized` store, which is a simple, thread-safe Store
for single-process scenarios.

If you need to use a different store, set it in the Client Config:

```ruby
Prometheus::Client.config.data_store = Prometheus::Client::DataStores::DataStore.new(store_specific_params)
```

NOTE: You **must** make sure to set the `data_store` before initializing any metrics.
If using Rails, you probably want to set up your Data Store on `config/application.rb`,
or `config/environments/*`, both of which run before `config/initializers/*`

Also note that `config.data_store` is set to an *instance* of a `DataStore`, not to the 
class. This is so that the stores can receive parameters. Most of the built-in stores
don't require any, but `DirectFileStore` does, for example.

When instantiating metrics, there is an optional `store_settings` attribute. This is used
to set up store-specific settings for each metric. For most stores, this is not used, but
for multi-process stores, this is used to specify how to aggregate the values of each
metric across multiple processes. For the most part, this is used for Gauges, to specify
whether you want to report the `SUM`, `MAX` or `MIN` value observed across all processes.
For almost all other cases, you'd leave the default (`SUM`). More on this on the 
*Aggregation* section below.

Other custom stores may also accept extra parameters besides `:aggregation`. See the
documentation of each store for more details.

### Built-in stores

There are 3 built-in stores, with different trade-offs:

- **Synchronized**: Default store. Thread safe, but not suitable for multi-process 
  scenarios (e.g. pre-fork servers, like Unicorn). Stores data in Hashes, with all accesses
  protected by Mutexes. 
- **SingleThreaded**: Fastest store, but only suitable for single-threaded scenarios.
  This store does not make any effort to synchronize access to its internal hashes, so 
  it's absolutely not thread safe.
- **DirectFileStore**: Stores data in binary files, one file per process and per metric.
  This is generally the recommended store to use with pre-fork servers and other 
  "multi-process" scenarios.

  Each metric gets a file for each process, and manages its contents by storing keys and
  binary floats next to them, and updating the offsets of those Floats directly. When 
  exporting metrics, it will find all the files that apply to each metric, read them, 
  and aggregate them.

  In order to do this, each Metric needs an `:aggregation` setting, specifying how
  to aggregate the multiple possible values we can get for each labelset. By default,
  they are `SUM`med, which is what most use-cases call for (counters and histograms,
  for example). However, for Gauges, it's possible to set `MAX` or `MIN` as aggregation, 
  to get the highest/lowest value of all the processes / threads.
  
  Even though this store saves data on disk, it's still much faster than would probably be 
  expected, because the files are never actually `fsync`ed, so the store never blocks 
  while waiting for disk. The kernel's page cache is incredibly efficient in this regard.
  
  If in doubt, check the benchmark scripts described in the documentation for creating 
  your own stores and run them in your particular runtime environment to make sure this 
  provides adequate performance.

### Building your own store, and stores other than the built-in ones.

If none of these stores is suitable for your requirements, you can easily make your own.

The interface and requirements of Stores are specified in detail in the `README.md`
in the `client/data_stores` directory. This thoroughly documents how to make your own 
store.

There are also links there to non-built-in stores created by others that may be useful,
either as they are, or as a starting point for making your own.

### Aggregation settings for multi-process stores

If you are in a multi-process environment (such as pre-fork servers like Unicorn), each
process will probably keep their own counters, which need to be aggregated when receiving
a Prometheus scrape, to report coherent total numbers.

For Counters and Histograms (and quantile-less Summaries), this is simply a matter of 
summing the values of each process.

For Gauges, however, this may not be the right thing to do, depending on what they're 
measuring. You might want to take the maximum or minimum value observed in any process,
rather than the sum of all of them.

In those cases, you should use the `store_settings` parameter when registering the 
metric, to specify an `:aggregation` setting. 

```ruby
free_disk_space = registry.gauge(:free_disk_space_bytes,
                                docstring: "Free disk space, in bytes",
                                store_settings: { aggregation: :max })
```

NOTE: This will only work if the store you're using supports the `:aggregation` setting.
Of the built-in stores, only `DirectFileStore` does.

Also note that the `:aggregation` setting works for all metric types, not just for gauges. 
It would be unusual to use it for anything other than gauges, but if your use-case 
requires it, the store will respect your aggregation wishes.

## Tests

Install necessary development gems with `bundle install` and run tests with
rspec:

```bash
rake
```

[1]: https://github.com/prometheus/prometheus
[2]: http://rack.github.io/
[3]: https://secure.travis-ci.org/prometheus/client_ruby.svg?branch=master
[4]: https://badge.fury.io/rb/prometheus-client.svg
[7]: https://coveralls.io/repos/prometheus/client_ruby/badge.svg?branch=master
[8]: https://github.com/prometheus/pushgateway
[9]: lib/prometheus/middleware/exporter.rb
[10]: lib/prometheus/middleware/collector.rb
