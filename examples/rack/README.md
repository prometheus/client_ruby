# Rack example

A simple Rack application which shows how to use prometheus' `Rack::Exporter`
and `Rack::Collector` rack middlwares.

## Usage

Start the Server.

```bash
unicorn -p 5000 -c unicorn.conf
```

Benchmark number of requests.

```bash
ab -c 10 -n 1000 http://127.0.0.1:5000/
```

View the metrics output.

```bash
curl http://127.0.0.1:5000/metrics.json
```
