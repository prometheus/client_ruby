# Rack example

A simple Rack application which shows how to use the included
`Prometheus::Middleware::Exporter` and `Prometheus::Middleware::Collector`
middlwares.

## Run the example

### Standalone

Execute the provided `run` script:

```bash
bundle install
bundle exec ./run
```

This will start the rack app, run a few requests against it, print the
output of `/metrics` and terminate.

### With a Prometheus server

Start a Prometheus server with the provided config:

```bash
prometheus -config.file ./prometheus.yml
```

In another terminal, start the application server:

```bash
bundle install
bundle exec unicorn -c ./unicorn.conf
```

You can now open the [example app](http://localhost:5000/) and its [metrics
page](http://localhost:5000/metrics) to inspect the output. The running
Prometheus server can be used to [play around with the metrics][rate-query].

[rate-query]: http://localhost:9090/graph#%5B%7B%22range_input%22%3A%221h%22%2C%22expr%22%3A%22rate(http_server_requests_total%5B1m%5D)%22%2C%22tab%22%3A0%7D%5D

## Collector

The example shown in [`config.ru`](config.ru) is a trivial rack application
using the default collector and exporter middlewares.

In order to use custom label builders in the collector, change the line to
something like this:

```ruby
use Prometheus::Middleware::Collector, counter_label_builder: ->(env, code) {
  next { code: nil, method: nil, host: nil, path: nil } if env.empty?

  {
    code:         code,
    method:       env['REQUEST_METHOD'].downcase,
    # Include the HTTP Host header as label.
    host:         env['HTTP_HOST'].to_s,
    # Include path, but replace all numeric IDs to keep cardinality low.
    # Think '/users/1234/comments' -> '/users/:id/comments'
    path:         env['PATH_INFO'].to_s.gsub(/\/\d+(\/|$)/, '/:id\\1'),
  }
}
```
