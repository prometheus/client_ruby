# Rack example

A simple Rack application which shows how to use prometheus' `Rack::Exporter`
and `Rack::Collector` rack middlwares.

## Run the example

Execute the provided `run` script:

```bash
./run
```

This will start the rack app, run a few requests against it and print the
output of `/metrics`.

## Overview

The example shown in [`config.ru`](config.ru) is a trivial rack application
using the available collector and exporter middlewares.

In order to use a custom label builder in the collector, change the line to
something like this:

```ruby
use Prometheus::Client::Rack::Collector do |env|
  {
    method:     env['REQUEST_METHOD'].downcase,
    host:       env['HTTP_HOST'].to_s,
    path:       env['PATH_INFO'].to_s,
    user_agent: env['HTTP_USER_AGENT'].to_s,
  }
end
```
