# Upgrading from 3.x.x to 4.x.x

## Objectives

4.0.0 contains a single breaking change - the [removal
of](https://github.com/prometheus/client_ruby/pull/251) [framework-specific route
detection](https://github.com/prometheus/client_ruby/pull/245) from
`Prometheus::Middleware::Collector`.

## Removal of framework-specific route detection

In 3.0.0 we added a feature that used specific information provided by the Sinatra and
Grape web frameworks to generate the `path` label in `Prometheus::Middleware::Collector`.

This feature turned out to be inherently flawed, due to limitations in the information we
can extract from the request environment. [This
comment](https://github.com/prometheus/client_ruby/issues/249#issuecomment-1061317511)
goes into much more depth on the investigation we did and the conclusions we came to.

Most users will be unaffected by this change. If you use Sinatra or Grape and
`Prometheus::Middleware::Collector` you will notice that your `path` label values will be
much more similar to the ones we generated in the 2.x.x release series.

# Upgrading from 2.x.x to 3.x.x

## Objectives

Most of the breaking changes in 3.0.0 are in `Prometheus::Client::Push`, which has had a
fairly major overhaul.

As well as that, there are a handful of smaller breaking changes.

## Ruby

The minimum supported Ruby version is now 2.6. This will change over time according to our
[compatibility policy](COMPATIBILITY.md).

## Push client improvements

### Keyword arguments

In line with changes we made for the 0.10.0 release (see below),
`Prometheus::Client::Push` now favours the use of keyword arguments for improved clarity
at the callsites. Specifically, the constructor now takes several keyword arguments rather
than relying entirely on positional arguments. Where you would previously have written:

```ruby
Prometheus::Client::Push.new('my-batch-job', 'some-instance', 'https://example.domain:1234')
```

you would now write:

```ruby
Prometheus::Client::Push.new(
  job: 'my-batch-job',
  gateway: 'https://example.domain:1234',
  grouping_key: { instance: 'some-instance', extra_key: 'foobar' }
).add(registry)
```

### Removal of `instance` in favour of `grouping_key`

Previously, it was possible to specify the instance of a job for which metrics were being
pushed, like:

```ruby
Prometheus::Client::Push.new('my-batch-job', 'some-instance').add(registry)
```

What this really did under-the-hood was set a grouping key with a single key-value pair in
it. The Pushgateway itself [supports arbitrary grouping
keys](https://github.com/prometheus/pushgateway#url) made up of many key-value pairs. We
now support submitting metrics with such grouping keys:

```ruby
Prometheus::Client::Push.new(
  job: 'my-batch-job',
  grouping_key: { instance: 'some-instance', extra_key: 'foobar' }
).add(registry)
```

### Separate method for setting basic auth credentials

Previously, when initializing a `Prometheus::Client::Push` instance with HTTP Basic
Authentication credentials, you would make a call like:

```ruby
push = Prometheus::Client::Push.new("my-job", "some-instance", "http://user:password@localhost:9091")
```

In most cases, this was fine, but would break if the user or password contained any
non-URL-safe characters ([per RFC
3986](https://datatracker.ietf.org/doc/html/rfc3986#section-2.1)).

While it is possible to pass those characters using percent-encoding, previous versions of
`Prometheus::Client::Push` didn't decode them before passing them into the HTTP client,
meaning that approach wouldn't work as the credentials we sent to the server would be
wrong.

We [discussed how to fix
it](https://github.com/prometheus/client_ruby/issues/170#issuecomment-1003765815) and
decided it would be better to have a separate method for supplying HTTP Basic
Authentication credentials, with no requirement for percent-encoding, than to make users
jump through the hoops of correctly encoding the username and password in the gateway URL.

In the 3.x.x release series, HTTP Basic Authentication credentials should be passed like
this:

```ruby
push = Prometheus::Client::Push.new(job: "my-job", gateway: "http://localhost:9091")
push.basic_auth("user", "password")
```

We also explicitly reject usernames and passwords being passed in the gateway URL, and
will raise an error if they are passed that way.

### Presence of `job` is now validated

We now validate that the `job` passed to the `Prometheus::Client::Push` initializer is not
`nil` and isn't the empty string.

### Raising errors on non-2xx responses from Pushgateway

Previously, if the Pushgateway (or a proxy between us and it) returned a non-2xx HTTP
response, we would silently fail to submit metrics to it.

Now, an appropriate error is raised, indicating which class of non-2xx response was
received. If you want to `rescue` those errors and handle them explicitly, they are all
subclasses of `Prometheus::Client::Push::HttpError`. If you only want to handle some of
them, or want to handle each class of non-2xx response differently, you can `rescue` one
or more of:

  - `Prometheus::Client::Push::HttpRedirectError`
  - `Prometheus::Client::Push::HttpClientError`
  - `Prometheus::Client::Push::HttpServerError`

_Note: `Prometheus::Client::Push` does not follow redirects. You should configure the
client to talk directly to an instance of the Pushgateway._

### Fixed encoding of spaces in `job` and `instance`

In a [previous
commit](https://github.com/prometheus/client_ruby/pull/188/commits/f31bdcb8eda943f8ddf720e0b9d65ac22124cc93)
we addressed the deprecation (and later removal in Ruby 3.0) of `URI.escape` by switching
to `CGI.escape` for encoding the values of `job` and `instance` which would ultimately end
up in the grouping key.

Unfortunately, this proved to be a subtly breaking change, as `CGI.escape` encodes spaces
(`" "`) as `"+"` rather than `"%20"`. This led to spaces in the values of `job` and
`instance` being turned into literal plus signs.

In 3.x.x, [we have
switched](https://github.com/prometheus/client_ruby/pull/220/commits/ec5c5aa6979aa295d91fbc16e76e5eb09f82a256)
to `ERB::Util::url_encode`, which handles this case correctly. You may notice your metrics
being published under a different grouping key as a result of this change (if either your
`job` or `instance` values contained spaces).

## Automatic initialization of time series with no labels

The [Prometheus documentation on best
practices](https://prometheus.io/docs/practices/instrumentation/#avoid-missing-metrics)
recommends exporting a default value for any time series you know will exist in advance.
For series with no labels, other Prometheus clients (including Go, Java, and Python) do
this automatically, so we have matched that behaviour in the 3.x.x series.

## Added `SCRIPT_NAME` to path labels in Collector middleware

Previously, we did not include `Rack::Request`'s `SCRIPT_NAME` when building paths in
`Prometheus::Middleware::Collector`. We have now added this, which means that any
application using the included collector middleware with a non-empty `SCRIPT_NAME` will
generate different path labels.

This will most typically be present when mounting several Rack applications in the same
server process, such as when using [Rails
Engines](https://guides.rubyonrails.org/engines.html).

## Improved stripping of IDs/UUIDs from paths in Collector middleware

Where available (currently for applications written in the Sinatra and Grape frameworks),
we now use framework-specific equivalents to `PATH_INFO` in
`Prometheus::Middleware::Collector`, which means that rather than having path segments
replaced with the generic `:id` and `:uuid` placeholders, you'll see the route as you
defined it in your framework.

For frameworks where that information isn't available to us (most notably Rails), we still
fall back to using `PATH_INFO`, though we have also improved how we strip IDs/UUIDs from
it. Previously, we would only strip them from alternating path segments due to the way we
were matching them. We have improved that matching so it works even when there are
IDs/UUIDs in consecutive path segments.

You may notice the path label change for some of your endpoints.

## Improved validation of label names

Earlier versions of the Ruby Prometheus client performed limited validation of label names
(e.g. ensuring that they didn't start with `__`). The validation rules for label names are
specified [in the Prometheus
documentation](https://prometheus.io/docs/concepts/data_model/#metric-names-and-labels),
and we now apply them during metric declaration. Specifically, we have added a check that
label names match the regex `[a-zA-Z_][a-zA-Z0-9_]*`.

Any labels previously let through by the lack of validation were invalid, and likely would
have caused problems when scraped by Prometheus server.

# Upgrading from 0.9 to 0.10.x

## Objectives

0.10.0 represents a big step forward for the Prometheus Ruby client, which comes with some
breaking changes. The objectives behind those changes are:

1. Bringing the Ruby client in line with [Prometheus conventions and best
   practices](https://prometheus.io/docs/instrumenting/writing_clientlibs/)
2. Adding support for multi-process web servers like Unicorn. This was done by introducing
   the notion of pluggable storage backends.

   The client can now be configured with different storage backends, and we provide 3 with
   the gem: thread-safe (default), thread-unsafe (best performance in single-threaded use
   cases), and a multi-process backend that can be used in forking web servers like
   Unicorn.

   Users of the library can build their own storage backend to support different
   use cases provided they conform to the same interface.

## Ruby

The minimum supported Ruby version is now 2.3. This will change over time according to our
[compatibility policy](COMPATIBILITY.md).

## Data Stores

The single biggest feature in this release is support for multi-process web servers.

The way this was achieved was by introducing a standard interface for metric storage
backends and providing implementations for the most common use-cases.

If you're using a multi-process web server, you'll want `DirectFileStore`, which
aggregates metrics across the processes.

```ruby
Prometheus::Client.config.data_store = Prometheus::Client::DataStores::DirectFileStore.new(dir: '/tmp/direct_file_store')
```

The default store is the `Synchronized` store, which provides a threadsafe implementation,
but one which doesn't work in multi-process scenarios.

If you're absolutely sure that you won't use multiple threads or processes, you can use the
`SingleThreaded` data store and avoid the locking overhead. Note that in almost all use
cases the performance overhead won't matter, which is why we use the `Synchronized` store
by default.

## Keyword arguments (kwargs)

Many multi-parameter methods have had their arguments changed to keyword arguments for
improved clarity at the callsite.

### 0.9
```ruby
counter = Prometheus::Client::Counter.new(:service_requests_total, '...')
```

### 0.10
```ruby
counter = Prometheus::Client::Counter.new(:service_requests_total, docstring: '...')
```

### Labels

Labels must now be declared at metric initialization. Observing a value with a label that
wasn't passed in at initialization will raise an error.

### 0.9

```ruby
counter = Prometheus::Client::Counter.new(:service_requests_total, '...')
counter.increment({ service: 'foo' })
```

### 0.10

```ruby
counter = Prometheus::Client::Counter.new(:service_requests_total, docstring: '...', labels: [:service])
counter.increment(labels: { service: 'foo' })
```

## Histograms

Keys in the hash returned from the get method are now strings.

Histograms now include a "+Inf" bucket as well as the sum of all observations.

### 0.9

```ruby
histogram = Prometheus::Client::Histogram.new(:service_latency_seconds, '...', {}, [0.1, 0.3, 1.2])

histogram.observe({ service: 'users' }, 0.1)
histogram.observe({ service: 'users' }, 0.3)
histogram.observe({ service: 'users' }, 0.4)
histogram.observe({ service: 'users' }, 1.2)
histogram.observe({ service: 'users' }, 1.5)

histogram.get({ service: 'users' })
# => {0.1=>1.0, 0.3=>2.0, 1.2=>4.0}
```
### 0.10

```ruby
histogram = Prometheus::Client::Histogram.new(:service_latency_seconds, docstring: '...', labels: [:service], buckets: [0.1, 0.3, 1.2])

histogram.observe(0.1, labels: { service: 'users' })
histogram.observe(0.3, labels: { service: 'users' })
histogram.observe(0.4, labels: { service: 'users' })
histogram.observe(1.2, labels: { service: 'users' })
histogram.observe(1.5, labels: { service: 'users' })

histogram.get(labels: { service: 'users' })
# => {"0.1"=>0.0, "0.3"=>1.0, "1.2"=>3.0, "+Inf"=>5.0, "sum"=>3.5}
```

## Summaries

Summaries no longer include quantiles. They include the sum and the count instead.

### 0.9

```ruby
summary = Prometheus::Client::Histogram.new(:service_latency_seconds, '...', {}, [0.1, 0.3, 1.2])

summary.observe({ service: 'users' }, 0.1)
summary.observe({ service: 'users' }, 0.3)
summary.observe({ service: 'users' }, 0.4)
summary.observe({ service: 'users' }, 1.2)
summary.observe({ service: 'users' }, 1.5)

summary.get({ service: 'users' })
# => {0.1=>1.0, 0.3=>2.0, 1.2=>4.0}
```
### 0.10

```ruby
summary = Prometheus::Client::Summary.new(:service_latency_seconds, docstring: '...', labels: [:service])

summary.observe(0.1, labels: { service: 'users' })
summary.observe(0.3, labels: { service: 'users' })
summary.observe(0.4, labels: { service: 'users' })
summary.observe(1.2, labels: { service: 'users' })
summary.observe(1.5, labels: { service: 'users' })

summary.get(labels: { service: 'users' })
# => {"count"=>5.0, "sum"=>3.5}
```

## Rack middleware

Because metric labels must be declared up front, we've removed support for customising the
labels set in the default Rack middleware we provide.

We did make an attempt to preserve that ability, but decided that the interface was too
confusing and removed it in #121. We might revisit this and have another try at a better
interface in the future.

## Extra reserved label: `pid`

When adding support for multi-process web servers, we realised that aggregating gauges
reported by individual processes (e.g. by summing them) is almost never what you want to
do.

We decided to expose each process's value individually, with a `pid` label set to
differentiate between the proesses. Because of that, `pid` is now a reserved label.
