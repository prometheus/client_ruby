# Prometheus Ruby Client

A suite of instrumentation metric primitives for Ruby that can be exposed
through a JSON web services interface. Intended to be used together with a
[Prometheus server][1].

[![Gem Version][4]](http://badge.fury.io/rb/prometheus-client)
[![Build Status][3]](http://travis-ci.org/prometheus/client_ruby)
[![Dependency Status][5]](https://gemnasium.com/prometheus/client_ruby)
[![Code Climate][6]](https://codeclimate.com/github/prometheus/client_ruby)
[![Coverage Status][7]](https://coveralls.io/r/prometheus/client_ruby?branch=master)

## Usage

### Library

```ruby
require 'prometheus/client'

# returns a default registry
prometheus = Prometheus::Client.registry

# create a new counter metric
http_requests = Prometheus::Client::Counter.new(:http_requests, 'A counter of HTTP requests made')
# register the metric
prometheus.register(http_requests)

# equivalent helper function
http_requests = prometheus.counter(:http_requests, 'A counter of HTTP requests made')

# start using the counter
http_requests.increment
```

### Rack middleware

There are two [Rack][2] middlewares available, one to expose a metrics HTTP
endpoint to be scraped by a prometheus server and one to trace all HTTP
requests.

```ruby
# config.ru

require 'rack'
require 'prometheus/client/rack/collector'
require 'prometheus/client/rack/exporter'

use Prometheus::Client::Rack::Collector
use Prometheus::Client::Rack::Exporter
run lambda { |env| [200, {'Content-Type' => 'text/html'}, ['OK']] }
```

Start the server and have a look at the metrics endpoint:
[http://localhost:5000/metrics](http://localhost:5000/metrics).

For further instructions and other scripts to get started, have a look at the
integrated [example application](examples/rack/README.md).

## Metrics

The following metric types are currently supported.

### Counter

Counter is a metric that exposes merely a sum or tally of things.

```ruby
counter = Prometheus::Client::Counter.new(:foo, '...')

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

Gauge is a metric that exposes merely an instantaneous value or some snapshot
thereof.

```ruby
gauge = Prometheus::Client::Gauge.new(:bar, '...')

# set a value
gauge.set({ role: 'base' }, 'up')

# retrieve the current value for a given label set
gauge.get({ role: 'problematic' })
# => 'down'
```

### Summary

Summary is an accumulator for samples. It captures Numeric data and provides
an efficient percentile calculation mechanism.

```ruby
summary = Prometheus::Client::Summary.new(:baz, '...')

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

Install necessary development gems with `bundle install` and run tests with
rspec:

```bash
rake
```

[1]: https://github.com/prometheus/prometheus
[2]: http://rack.github.io/
[3]: https://secure.travis-ci.org/prometheus/client_ruby.png?branch=master
[4]: https://badge.fury.io/rb/prometheus-client.svg
[5]: https://gemnasium.com/prometheus/client_ruby.svg
[6]: https://codeclimate.com/github/prometheus/client_ruby.png
[7]: https://coveralls.io/repos/prometheus/client_ruby/badge.png?branch=master
