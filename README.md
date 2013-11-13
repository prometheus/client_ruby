# Prometheus Ruby Client

## Usage

```ruby
require 'prometheus/client'

# returns a default registry
prometheus = Prometheus::Client.registry

# create a new counter metric
http_requests = Prometheus::Client::Counter.new

# register the metric
prometheus.register(:http_requests, 'A counter of the total number of HTTP requests made', http_requests)

# start using the counter
http_requests.increment
```

## Metrics

The following metric types are currently supported.

### Counter

A Counter is a metric that exposes merely a sum or tally of things.

```ruby
counter = Prometheus::Client::Counter.new

# increment the counter for a given label set
counter.increment(service: 'foo')

# increment by a given value
counter.increment({ service: 'bar' }, 5)

# decrement the counter
counter.decrement(service: 'exceptional')

# get current value for a given label set
counter.get(service: 'bar')
# => 5
```

### Gauge

A Gauge is a metric that exposes merely an instantaneous value or some
snapshot thereof.

```ruby
gauge = Prometheus::Client::Gauge.new

# set a value
gauge.set({ role: 'base' }, 'up')

# retrieve the current value for a given label set
gauge.get({ role: 'problematic' })
# => 'down'
```

### Summary

The Summary is an accumulator for samples. It captures Numeric data and provides
an efficient percentile calculation mechanism.

```ruby
summary = Prometheus::Client::Summary.new

# record a value
summary.add({ service: 'slow' }, Benchmark.realtime { service.call(arg) })

# retrieve the current quantile values
summary.get({ service: 'database' })
# => { 0.5: 1.233122, 0.9: 83.4323, 0.99: 341.3428231 }
```

## Todo

  * add push support to a vanilla prometheus exporter
  * use a more performant JSON library
  * add protobuf support

## Tests

[![Build Status][1]](http://travis-ci.org/prometheus/client_ruby)

Install necessary development gems with `bundle install` and run tests with
rspec:

```bash
rspec
```

[1]: https://secure.travis-ci.org/prometheus/client_ruby.png?branch=master
