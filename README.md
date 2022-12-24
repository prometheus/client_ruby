# Prometheus Ruby Client

A suite of instrumentation metric primitives for Ruby that can be exposed
through a HTTP interface. Intended to be used together with a
[Prometheus server][1].

[![Gem Version][4]](http://badge.fury.io/rb/prometheus-client)
[![Build Status][3]](https://circleci.com/gh/prometheus/client_ruby/tree/main.svg?style=svg)

## Usage

### Installation

For a global installation run `gem install prometheus-client`.

If you're using [Bundler](https://bundler.io/) add `gem "prometheus-client"` to your `Gemfile`.
Make sure to run `bundle install` afterwards.

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

run ->(_) { [200, {'content-type' => 'text/html'}, ['OK']] }
```

Start the server and have a look at the metrics endpoint:
[http://localhost:5123/metrics](http://localhost:5123/metrics).

For further instructions and other scripts to get started, have a look at the
integrated [example application](examples/rack/README.md).

### Pushgateway

The Ruby client can also be used to push its collected metrics to a
[Pushgateway][8]. This comes in handy with batch jobs or in other scenarios
where it's not possible or feasible to let a Prometheus server scrape a Ruby
process. TLS and HTTP basic authentication are supported.

```ruby
require 'prometheus/client'
require 'prometheus/client/push'

registry = Prometheus::Client.registry
# ... register some metrics, set/increment/observe/etc. their values

# push the registry state to the default gateway
Prometheus::Client::Push.new(job: 'my-batch-job').add(registry)

# optional: specify a grouping key that uniquely identifies a job instance, and gateway.
#
# Note: the labels you use in the grouping key must not conflict with labels set on the
# metrics being pushed. If they do, an error will be raised.
Prometheus::Client::Push.new(
  job: 'my-batch-job',
  gateway: 'https://example.domain:1234',
  grouping_key: { instance: 'some-instance', extra_key: 'foobar' }
).add(registry)

# If you want to replace any previously pushed metrics for a given grouping key,
# use the #replace method.
#
# Unlike #add, this will completely replace the metrics under the specified grouping key
# (i.e. anything currently present in the pushgateway for the specified grouping key, but
# not present in the registry for that grouping key will be removed).
#
# See https://github.com/prometheus/pushgateway#put-method for a full explanation.
Prometheus::Client::Push.new(job: 'my-batch-job').replace(registry)

# If you want to delete all previously pushed metrics for a given grouping key,
# use the #delete method.
Prometheus::Client::Push.new(job: 'my-batch-job').delete
```

#### Basic authentication

By design, `Prometheus::Client::Push` doesn't read credentials for HTTP basic
authentication when they are passed in via the gateway URL using the
`http://user:password@example.com:9091` syntax, and will in fact raise an error if they're
supplied that way.

The reason for this is that when using that syntax, the username and password
have to follow the usual rules for URL encoding of characters [per RFC
3986](https://datatracker.ietf.org/doc/html/rfc3986#section-2.1).

Rather than place the burden of correctly performing that encoding on users of this gem,
we decided to have a separate method for supplying HTTP basic authentication credentials,
with no requirement to URL encode the characters in them.

Instead of passing credentials like this:

```ruby
push = Prometheus::Client::Push.new(job: "my-job", gateway: "http://user:password@localhost:9091")
```

please pass them like this:

```ruby
push = Prometheus::Client::Push.new(job: "my-job", gateway: "http://localhost:9091")
push.basic_auth("user", "password")
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

Histograms provide default buckets of `[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]`

You can specify your own buckets, either explicitly, or using the `Histogram.linear_buckets`
or `Histogram.exponential_buckets` methods to define regularly spaced buckets.

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
summary_value['sum'] # => 123.45
summary_value['count'] # => 100
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

### `init_label_set`

The time series of a metric are not initialized until something happens. For counters, for example, this means that the time series do not exist until the counter is incremented for the first time.

To get around this problem the client provides the `init_label_set` method that can be used to initialise the time series of a metric for a given label set.

### Reserved labels

The following labels are reserved by the client library, and attempting to use them in a
metric definition will result in a
`Prometheus::Client::LabelSetValidator::ReservedLabelError` being raised:

  - `:job`
  - `:instance`
  - `:pid`

## Data Stores

The data for all the metrics (the internal counters associated with each labelset)
is stored in a global Data Store object, rather than in the metric objects themselves.
(This "storage" is ephemeral, generally in-memory, it's not "long-term storage")

The main reason to do this is that different applications may have different requirements
for their metrics storage. Applications running in pre-fork servers (like Unicorn, for
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
whether you want to report the `SUM`, `MAX`, `MIN`, or `MOST_RECENT` value observed across
all processes. For almost all other cases, you'd leave the default (`SUM`). More on this
on the *Aggregation* section below.

Custom stores may also accept extra parameters besides `:aggregation`. See the
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
  "multi-process" scenarios. There are some important caveats to using this store, so
  please read on the section below.

### `DirectFileStore` caveats and things to keep in mind

Each metric gets a file for each process, and manages its contents by storing keys and
binary floats next to them, and updating the offsets of those Floats directly. When
exporting metrics, it will find all the files that apply to each metric, read them,
and aggregate them.

**Aggregation of metrics**: Since there will be several files per metrics (one per process),
these need to be aggregated to present a coherent view to Prometheus. Depending on your
use case, you may need to control how this works. When using this store,
each Metric allows you to specify an `:aggregation` setting, defining how
to aggregate the multiple possible values we can get for each labelset. By default,
Counters, Histograms and Summaries are `SUM`med, and Gauges report all their values (one
for each process), tagged with a `pid` label. You can also select `SUM`, `MAX`, `MIN`, or
`MOST_RECENT` for your gauges, depending on your use case.

Please note that the `MOST_RECENT` aggregation only works for gauges, and it does not
allow the use of `increment` / `decrement`, you can only use `set`.

**Memory Usage**: When scraped by Prometheus, this store will read all these files, get all
the values and aggregate them. We have notice this can have a noticeable effect on memory
usage for your app. We recommend you test this in a realistic usage scenario to make sure
you won't hit any memory limits your app may have.

**Resetting your metrics on each run**: You should also make sure that the directory where
you store your metric files (specified when initializing the `DirectFileStore`) is emptied
when your app starts. Otherwise, each app run will continue exporting the metrics from the
previous run.

If you have this issue, one way to do this is to run code similar to this as part of you
initialization:

```ruby
Dir["#{app_path}/tmp/prometheus/*.bin"].each do |file_path|
  File.unlink(file_path)
end
```

If you are running in pre-fork servers (such as Unicorn or Puma with multiple processes),
make sure you do this **before** the server forks. Otherwise, each child process may delete
files created by other processes on *this* run, instead of deleting old files.

**Declare metrics before fork**: As well as deleting files before your process forks, you
should make sure to declare your metrics before forking too. Because the metric registry
is held in memory, any metrics declared after forking will only be present in child
processes where the code declaring them ran, and as a result may not be consistently
exported when scraped (i.e. they will only appear when a child process that declared them
is scraped).

If you're absolutely sure that every child process will run the metric declaration code,
then you won't run into this issue, but the simplest approach is to declare the metrics
before forking.

**Large numbers of files**: Because there is an individual file per metric and per process
(which is done to optimize for observation performance), you may end up with a large number
of files. We don't currently have a solution for this problem, but we're working on it.

**Performance**: Even though this store saves data on disk, it's still much faster than
would probably be expected, because the files are never actually `fsync`ed, so the store
never blocks while waiting for disk. The kernel's page cache is incredibly efficient in
this regard. If in doubt, check the benchmark scripts described in the documentation for
creating your own stores and run them in your particular runtime environment to make sure
this provides adequate performance.


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

For Counters, Histograms and quantile-less Summaries this is simply a matter of
summing the values of each process.

For Gauges, however, this may not be the right thing to do, depending on what they're
measuring. You might want to take the maximum or minimum value observed in any process,
rather than the sum of all of them. By default, we export each process's individual
value, with a `pid` label identifying each one.

If these defaults don't work for your use case, you should use the `store_settings`
parameter when registering the metric, to specify an `:aggregation` setting.

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
[3]: https://circleci.com/gh/prometheus/client_ruby/tree/main.svg?style=svg
[4]: https://badge.fury.io/rb/prometheus-client.svg
[8]: https://github.com/prometheus/pushgateway
[9]: lib/prometheus/middleware/exporter.rb
[10]: lib/prometheus/middleware/collector.rb
