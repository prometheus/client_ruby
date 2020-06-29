# CHANGELOG

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
