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
prometheus --config.file ./prometheus.yml
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

Currently, the collector middleware doesn't offer any flexibility around label
keys or values (see #111). If you have more sophisticated requirements, we
recommend creating your own collector middleware.

If your requirements are minimal, one option is to subclass
`Prometheus::Middleware::Collector` and override the methods you need to. For
example, if you want to [change the way IDs are stripped from the
path](https://github.com/prometheus/client_ruby/blob/982fe2e3c37e2940d281573c7689224152dd791f/lib/prometheus/middleware/collector.rb#L97-L101)
you could override the appropriate method:

```ruby
require 'prometheus/middleware/collector'

class MyCollector < Prometheus::Middleware::Collector
  def strip_ids_from_path(path)
    super(path)
      .gsub(/8675309/, ':jenny\\1')
  end
end
```

and use your class in `config.ru` instead.

If you want to completely customise how the `path` label is generated, you can
override `generate_path`. For example, to use
[Sinatra](https://github.com/sinatra/sinatra)'s framework-specific route info
from the request environment:

```ruby
require 'prometheus/middleware/collector'

class MyCollector < Prometheus::Middleware::Collector
  def generate_path(env)
    # `sinatra.route` contains both the request method and the route, separated
    # by a space (e.g. "GET /payments/:id"). To get just the request path, you
    # can partition the string on " ".
    env['sinatra.route'].partition(' ').last
  end
end
```

Just make sure that your custom path generation logic strips IDs from the path
it returns, or gets the path from a source that would never contain them in the
first place (such as `sinatra.route`), otherwise you'll generate a huge number
of label values!

**Note:** `Prometheus::Middleware::Collector` isn't explicitly designed to be
subclassed, so the internals are liable to change at any time, including in
patch releases. Overriding its methods is done at your own risk!
