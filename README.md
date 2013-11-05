# Prometheus Ruby Client

## Usage

```ruby
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

### Gauge

A Gauge is a metric that exposes merely an instantaneous value or some
snapshot thereof.

## Todo

  * add histogram support
  * add push support to a vanilla prometheus exporter
  * add tests for Rack middlewares
  * use a more performant JSON library

## Tests

[![Build Status][1]](http://travis-ci.org/prometheus/client_ruby)

Install necessary development gems with `bundle install` and run tests with
rspec:

```bash
rspec
```

[1]: https://secure.travis-ci.org/prometheus/client_ruby.png?branch=master
