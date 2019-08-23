# Upgrading from 0.9 to 0.10.x

## Objectives

0.10.0 represents a big step forward for the Prometheus Ruby client, which comes with some
breaking changes. The objectives behind those changes are:

1. Bringing the Ruby client in line with [Prometheus conventions and best
   practices](https://prometheus.io/docs/instrumenting/writing_clientlibs/)
2. Adding support for multi-process web servers like Unicorn. This was done by introducing
   the notion of pluggable storage backends.

   The client can now be configured with different storage backends, and we provide 3 with
   the gem: thread-safe (default), thread-unsafe (best performance in single-threaded use
   cases), and a multi-process backend that can be used in forking web servers like
   Unicorn.

   Users of the library can build their own storage backend to support different
   use cases provided they conform to the same interface.

## Ruby

The minimum supported Ruby version is now 2.3. This will change over time according to our
[compatibility policy](COMPATIBILITY.md).

## Data Stores

The single biggest feature in this release is support for multi-process web servers.

The way this was achieved was by introducing a standard interface for metric storage
backends and providing implementations for the most common use-cases.

If you're using a multi-process web server, you'll want `DirectFileStore`, which
aggregates metrics across the processes.

```ruby
Prometheus::Client.config.data_store = Prometheus::Client::DataStores::DirectFileStore.new(dir: '/tmp/direct_file_store')
```

The default store is the `Synchronized` store, which provides a threadsafe implementation,
but one which doesn't work in multi-process scenarios.

If you're absolutely sure that you won't use multiple threads or processes, you can use the
`SingleThreaded` data store and avoid the locking overhead. Note that in almost all use
cases the performance overhead won't matter, which is why we use the `Synchronized` store
by default.

## Keyword arguments (kwargs)

Many multi-parameter methods have had their arguments changed to keyword arguments for
improved clarity at the callsite.

### 0.9
```ruby
counter = Prometheus::Client::Counter.new(:service_requests_total, '...')
```

### 0.10
```ruby
counter = Prometheus::Client::Counter.new(:service_requests_total, docstring: '...')
```

### Labels

Labels must now be declared at metric initialization. Observing a value with a label that
wasn't passed in at initialization will raise an error.

### 0.9

```ruby
counter = Prometheus::Client::Counter.new(:service_requests_total, '...')
counter.increment({ service: 'foo' })
```

### 0.10

```ruby
counter = Prometheus::Client::Counter.new(:service_requests_total, docstring: '...', labels: [:service])
counter.increment(labels: { service: 'foo' })
```

## Histograms

Keys in the hash returned from the get method are now strings.

Histograms now include a "+Inf" bucket as well as the sum of all observations.

### 0.9

```ruby
histogram = Prometheus::Client::Histogram.new(:service_latency_seconds, '...', {}, [0.1, 0.3, 1.2])

histogram.observe({ service: 'users' }, 0.1)
histogram.observe({ service: 'users' }, 0.3)
histogram.observe({ service: 'users' }, 0.4)
histogram.observe({ service: 'users' }, 1.2)
histogram.observe({ service: 'users' }, 1.5)

histogram.get({ service: 'users' })
# => {0.1=>1.0, 0.3=>2.0, 1.2=>4.0}
```
### 0.10

```ruby
histogram = Prometheus::Client::Histogram.new(:service_latency_seconds, docstring: '...', labels: [:service], buckets: [0.1, 0.3, 1.2])

histogram.observe(0.1, labels: { service: 'users' })
histogram.observe(0.3, labels: { service: 'users' })
histogram.observe(0.4, labels: { service: 'users' })
histogram.observe(1.2, labels: { service: 'users' })
histogram.observe(1.5, labels: { service: 'users' })

histogram.get(labels: { service: 'users' })
# => {"0.1"=>0.0, "0.3"=>1.0, "1.2"=>3.0, "+Inf"=>5.0, "sum"=>3.5}
```

## Summaries

Summaries no longer include quantiles. They include the sum and the count instead.

### 0.9

```ruby
summary = Prometheus::Client::Histogram.new(:service_latency_seconds, '...', {}, [0.1, 0.3, 1.2])

summary.observe({ service: 'users' }, 0.1)
summary.observe({ service: 'users' }, 0.3)
summary.observe({ service: 'users' }, 0.4)
summary.observe({ service: 'users' }, 1.2)
summary.observe({ service: 'users' }, 1.5)

summary.get({ service: 'users' })
# => {0.1=>1.0, 0.3=>2.0, 1.2=>4.0}
```
### 0.10

```ruby
summary = Prometheus::Client::Summary.new(:service_latency_seconds, docstring: '...', labels: [:service])

summary.observe(0.1, labels: { service: 'users' })
summary.observe(0.3, labels: { service: 'users' })
summary.observe(0.4, labels: { service: 'users' })
summary.observe(1.2, labels: { service: 'users' })
summary.observe(1.5, labels: { service: 'users' })

summary.get(labels: { service: 'users' })
# => {"count"=>5.0, "sum"=>3.5}
```

## Rack middleware

Because metric labels must be declared up front, we've removed support for customising the
labels set in the default Rack middleware we provide.

We did make an attempt to preserve that ability, but decided that the interface was too
confusing and removed it in #121. We might revisit this and have another try at a better
interface in the future.

## Extra reserved label: `pid`

When adding support for multi-process web servers, we realised that aggregating gauges
reported by individual processes (e.g. by summing them) is almost never what you want to
do.

We decided to expose each process's value individually, with a `pid` label set to
differentiate between the proesses. Because of that, `pid` is now a reserved label.
