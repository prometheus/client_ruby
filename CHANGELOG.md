# CHANGELOG

# Upcoming 3.0.0 / 2021-??-?? (not released yet, these are the merged PRs we'll release)

This new major version includes some breaking changes. They should be reasonably easy to
adapt to, but please read the details below:

## Breaking changes

- [#206](https://github.com/prometheus/client_ruby/pull/206) Include SCRIPT_NAME when 
    determining path in Collector:  
    When determining the path for a request, Rack::Request prefixes the
    SCRIPT_NAME. This was a problem with our code when using mountable engines,
    where the engine part of the path gets lost. This patch fixes that to include SCRIPT_NAME as part of the path.
    
    **This may be a breaking change**. Labels may change in existing metrics.  

- [#209](https://github.com/prometheus/client_ruby/pull/209) Automatically initialize metrics
    without labels.  
    Following the [Prometheus Best Practices](https://prometheus.io/docs/practices/instrumentation/#avoid-missing-metrics), 
    client libraries are expected to automatically export a 0 value when declaring a metric 
    that has no labels.  
    We missed this recommendation in the past, and this wasn't happening. Starting from this 
    version, all metrics without labels will be immediately exported with `0` value, without
    need for an increment / observation. 
    
    **This may be a breaking change**. Depending on your particular metrics, this may
    result in a significant increase to the number of time series being exported. We 
    recommend you test this and make sure it doesn't cause problems.  

- [#220](https://github.com/prometheus/client_ruby/pull/220) Improvements to PushGateway client:  
    - The `job` parameter is now mandatory when instantiating `Prometheus::Client::Push` 
        and will raise `ArgumentError` if not specified, or if `nil` or an empty string/object
        are passed.
    - The `Prometheus::Client::Push` initializer now takes keyword arguments.
    - We now correctly handle an empty value for `instance` when generating the path to
        the PushGateway. 
    - Fixed URI escaping of spaces in the path to PushGateway. In the past, spaces were
        being encoded as `+` instead of `%20`, which is invalid.
        
    **This is a breaking change if you use Pushgateway**. You will need to update your
    code to pass keyword arguments to the `Prometheus::Client::Push` initializer.
    

# 2.2.0 / 2021-06-?? <-- TODO: update this date when we merge this and cut the new version

## New Features

- [#199](https://github.com/prometheus/client_ruby/pull/199) Add `port` filtering option
    to Exporter middleware.  
    You can now specify a `port` when adding `Prometheus::Middleware::Exporter` to your
    middleware chain, and metrics will only be exported if the `/metrics` request comes
    through that port.

- [#222](https://github.com/prometheus/client_ruby/pull/222) Enable configuring `Net::HTTP` 
    timeouts for PushGateway calls.  
    You can now specify `open_timeout` and `read_timeout` when instantiating 
    `Prometheus::Client::Push`, to control these timeouts.

## Code improvements and bug fixes

- [#201](https://github.com/prometheus/client_ruby/pull/201) Make all registry methods 
    thread safe.

- [#227](https://github.com/prometheus/client_ruby/pull/227) Fix `with_labels` bug that 
    made it completely non-functional, and occasionally resulted in `DirectFileStore` file 
    corruption.


# 2.1.0 / 2020-06-29

## New Features

- [#177](https://github.com/prometheus/client_ruby/pull/177) Added Histogram helpers to 
    generate linear and exponential buckets, as the Client Library Guidelines recommend.
- [#172](https://github.com/prometheus/client_ruby/pull/172) Added :most_recent 
    aggregation for gauges on DirectFileStore.
    
## Code improvements

- Fixed several warnings that started firing in the latest versions of Ruby.

# 2.0.0 / 2020-01-28

## Breaking changes

- [#176](https://github.com/prometheus/client_ruby/pull/176) BUGFIX: Values observed at 
    the upper limit of a histogram bucket are now counted in that bucket, not the following
    one. This is unlikely to break functionality and you probably don't need to make code
    changes, but it may break tests.

## New features

- [#156](https://github.com/prometheus/client_ruby/pull/156) Added `init_label_set` method,
    which allows declaration of time series on app startup, starting at 0.


# 1.0.0 / 2019-11-04

## Breaking changes

- This release saw a number of breaking changes to better comply with latest best practices
  for naming and client behaviour. Please refer to [UPGRADING.md](UPGRADING.md) for details
  if upgrading from `<= 0.9`.
  
- The main feature of this release was adding support for multi-process environments such
  as pre-fork servers (Unicorn, Puma).
