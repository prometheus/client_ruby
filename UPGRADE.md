# Upgrade from 0.9 to 1.x

## Objectives

This major upgrade achieves the following objectives:

1. Follow [client conventions and best practices](https://prometheus.io/docs/instrumenting/writing_clientlibs/)
2. Add the notion of Pluggable backends. Client should be configurable with different backends: thread-safe (default), thread-unsafe (lock-free for performance on single-threaded cases), multiprocess, etc.
Consumers should be able to build and plug their own backends based on their use cases.

## Ruby

The minimum supported Ruby version is 2.0.0.

## Data Stores

You can specify the data store implementation depending on your needs.

For example, if you are running a pre-fork application using Unicorn you will need a way to aggregate the metrics from each of your workers before Prometheus scrapes them.

This can be achieved with DirectFileStore.

```ruby
Prometheus::Client.config.data_store = Prometheus::Client::DataStores::DirectFileStore.new(dir: '/tmp/direct_file_store')
```

## kwargs

Certain parameters are now keyword arguments.

### 0.9
```ruby
counter = Prometheus::Client::Counter.new(:service_requests_total, '...')
```

### 1.x
```ruby
counter = Prometheus::Client::Counter.new(:service_requests_total, docstring: '...')
```

### Labels

Labels are set when the metric is defined as opposed to when it is first used.

### 0.9

```ruby
counter = Prometheus::Client::Counter.new(:service_requests_total, '...')
counter.increment({ service: 'foo' })
```

### 1.x

```ruby
counter = Prometheus::Client::Counter.new(:service_requests_total, docstring: '...', labels: [:service])
counter.increment(labels: { service: 'foo' })
```

## Histograms

Keys from the get method are now strings.

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
### 1.x

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

Keys from the get method are now strings.

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
### 1.x

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