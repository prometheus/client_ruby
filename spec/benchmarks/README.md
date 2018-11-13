# Performance Benchmarks

The intention behind these benchmarks is twofold:

- On the one hand, if you have performance concerns for your counters, they'll allow you
  to simulate a reasonably realistic scenario, with your particular runtime characteristics,
  so you can know what kind of performance to expect under different circumstances, and pick
  settings accordingly.

- On the other hand, if you are developing your own Custom Data Store (more on this in
  `/lib/prometheus/client/data_stores/README.md), this will allow you to test how it 
  performs compared to the built-in ones, and also "system test" it to validate that it
  behaves appropriately.
  
## Benchmarks included

### Data Stores Performance

The Prometheus Ruby Client ships with different built-in data stores, optimized for 
different common scenarios (more on this on the repo's main README, under `Data Stores`).

This benchmark can show you, for your particular runtime environment, what kind of 
performance you can expect from each, to pick the one that's best for you.

More importantly, in a case where the built-in stores may not be useful for your 
particular circumstances, you might want to make your own Data Store. If that is the case,
this benchmark will help you compare its performance characteristics to the built-in 
stores, and will also run an export after the observations are made, and compare it with
the built-in ones, helping you catch potential bugs in your store, if the output doesn't
match.

The benchmark was made to try and simulate a somewhat realistic scenario, with plenty of
high-cardinality metrics, which is what you should be aiming for. It has a balance of 
counters and histograms, different label counts for different metrics, different thread
counts, etc. All this should be easy to customize to your particular needs by modifying 
the constants in the benchmark to tailor to what you need to measure.

In particular, if going for the goal of "how long it should take to increment a counter",
you probably want to have no labels and no histograms, since that's the reference 
performance measurement we use. 

### Labels Performance

Adding labels to your metrics can have significant performance impact, on two fronts:

- Labels passed in on every observation need to be validated. This may be alleviated by 
  using `with_labels`. If used to pre-set *all* labels, you can save a good
  amount of processing time, by skipping validation on each observation. This may be 
  important if you're incrementing metrics on a tight loop, and this benchmark can help
  with establishing what's to be expected.
  
- Even when caching them, these labels are keys to Hashes, they need to sometimes be 
  serialized into strings, sometimes merged into other hashes. All this incurs performance
  costs. This benchmark will allow you to estimate how much impact they can have. Again,
  if incrementing metrics on a tight loop, this will let you estimate whether you might
  want to have fewer labels instead.
  
It should be easy to modify the constants in this benchmark to your particular situation,
if necessary.

## Running the benchmarks

Simply run, from the repo's root directory:

`bundle exec ruby spec/benchmarks/labels.rb`
`bundle exec ruby spec/benchmarks/data_stores.rb`

