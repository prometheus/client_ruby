# Prometheus Ruby Client

A suite of instrumentation metric primitives for Ruby that can be exposed
through a HTTP interface. Intended to be used together with a
[Prometheus server][1].

[![Gem Version][4]](http://badge.fury.io/rb/prometheus-client)
[![Build Status][3]](http://travis-ci.org/prometheus/client_ruby)
[![Dependency Status][5]](https://gemnasium.com/prometheus/client_ruby)
[![Code Climate][6]](https://codeclimate.com/github/prometheus/client_ruby)
[![Coverage Status][7]](https://coveralls.io/r/prometheus/client_ruby)

## Usage

### Overview

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
counter = Prometheus::Client::Counter.new(:service_requests_total, '...')

# increment the counter for a given label set
counter.increment({ service: 'foo' })

# increment by a given value
counter.increment({ service: 'bar' }, 5)

# get current value for a given label set
counter.get({ service: 'bar' })
# => 5
```

### Gauge

Gauge is a metric that exposes merely an instantaneous value or some snapshot
thereof.

```ruby
gauge = Prometheus::Client::Gauge.new(:room_temperature_celsius, '...')

# set a value
gauge.set({ room: 'kitchen' }, 21.534)

# retrieve the current value for a given label set
gauge.get({ room: 'kitchen' })
# => 21.534

# increment the value (default is 1)
gauge.increment({ room: 'kitchen' })
# => 22.534

# decrement the value by a given value
gauge.decrement({ room: 'kitchen' }, 5)
# => 17.534
```

### Histogram

A histogram samples observations (usually things like request durations or
response sizes) and counts them in configurable buckets. It also provides a sum
of all observed values.

```ruby
histogram = Prometheus::Client::Histogram.new(:service_latency_seconds, '...')

# record a value
histogram.observe({ service: 'users' }, Benchmark.realtime { service.call(arg) })

# retrieve the current bucket values
histogram.get({ service: 'users' })
# => { 0.005 => 3, 0.01 => 15, 0.025 => 18, ..., 2.5 => 42, 5 => 42, 10 = >42 }
```

### Usage with Rails

To use this with Rails, mount the middlewares by modifying your **config.ru** file

```
# This file is used by Rack-based servers to start the application.

require ::File.expand_path('../config/environment', __FILE__)
require 'prometheus/middleware/collector'
require 'prometheus/middleware/exporter'

use Prometheus::Middleware::Collector
use Prometheus::Middleware::Exporter

run Rails.application

```

### Securing endpoint in a Rails application


When hosting **client_ruby** in a Rails app, you will probably want to secure the **/metrics** endpoint. This can be done using HTTP basic auth, assuming you are running your app over HTTPS.

Modify your **config.ru** as in the following [example](https://github.com/crowdAI/crowdai/blob/master/config.ru). In this case we are using an environment variable, CROWDAI_API_KEY, to store the password for basic auth.

```
# This file is used by Rack-based servers to start the application.

require ::File.expand_path('../config/environment', __FILE__)
require 'prometheus/middleware/collector'
require 'prometheus/middleware/exporter'

rackapp = Rack::Builder.app do
  use Prometheus::Middleware::Collector

  map '/metrics' do
    use Rack::Auth::Basic, 'Prometheus Metrics' do |username, password|
      Rack::Utils.secure_compare(ENV['CROWDAI_API_KEY'], password)
    end
    use Rack::Deflater
    use Prometheus::Middleware::Exporter, path: ''
    run ->(_) { [500, { 'Content-Type' => 'text/html' }, ['crowdAI metrics endpoint is unreachable!']] }
  end

  run Rails.application
end
run rackapp
```

Thanks to [this issue](https://github.com/prometheus/client_ruby/issues/61) and [this blog post](https://www.robustperception.io/instrumenting-a-ruby-on-rails-application-with-prometheus).

### Summary

Summary, similar to histograms, is an accumulator for samples. It captures
Numeric data and provides an efficient percentile calculation mechanism.

```ruby
summary = Prometheus::Client::Summary.new(:service_latency_seconds, '...')

# record a value
summary.observe({ service: 'database' }, Benchmark.realtime { service.call() })

# retrieve the current quantile values
summary.get({ service: 'database' })
# => { 0.5 => 0.1233122, 0.9 => 3.4323, 0.99 => 5.3428231 }
```

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
[5]: https://gemnasium.com/prometheus/client_ruby.svg
[6]: https://codeclimate.com/github/prometheus/client_ruby.svg
[7]: https://coveralls.io/repos/prometheus/client_ruby/badge.svg?branch=master
[8]: https://github.com/prometheus/pushgateway
[9]: lib/prometheus/middleware/exporter.rb
[10]: lib/prometheus/middleware/collector.rb
