# Custom Data Stores

Stores are basically an abstraction over a Hash, whose keys are in turn a Hash of labels
plus a metric name. The intention behind having different data stores is solving 
different requirements for different production scenarios, or performance trade-offs.

The most common of these scenarios are pre-fork servers like Unicorn, which have multiple
separate processes gathering metrics. If each of these had their own store, the metrics
reported on each Prometheus scrape would be different, depending on which process handles
the request. Solving this requires some sort of shared storage between these processes, 
and there are many ways to solve this problem, each with their own trade-offs.

This abstraction allows us to easily plug in the most adequate store for each scenario.

## Interface
   
`Store` exposes a `for_metric` method, which returns a store-specific and metric-specific 
`MetricStore` object, which represents a "view" onto the actual internal storage for one
particular metric. Each metric / collector object will have a references to this 
`MetricStore` and interact with it directly. 

The `MetricStore` class must expose `synchronize`, `set`, `increment`, `get` and `all_values`
methods,  which are explained in the code sample below. Its initializer should be called 
only by `Store#for_metric`, not directly.

All values stored are `Float`s.

Internally, a `Store` can store the data however it needs to, based on its requirements. 
For example, a store that needs to work in a multi-process environment needs to have a 
shared section of memory, via either Files, an MMap, an external database, or whatever the 
implementor chooses for their particular use case.

Each `Store` / `MetricStore` will also choose how to divide responsibilities over the 
storage of values. For some use cases, each `MetricStore` may have their own individual 
storage, whereas for others, the `Store` may own a central storage, and `MetricStore` 
objects will access it through the `Store`. This depends on the design choices of each `Store`. 

`Store` and `MetricStore` MUST be thread safe. This applies not only to operations on 
stored values (`set`, `increment`), but `MetricStore` must also expose a `synchronize`
method that would allow a Metric to increment multiple values atomically (Histograms need
this, for example).

Ideally, multiple keys should be modifiable simultaneously, but this is not a
hard requirement.

This is what the interface looks like, in practice:

```ruby
module Prometheus
  module Client
    module DataStores
      class CustomStore
      
        # Return a MetricStore, which provides a view of the internal data store, 
        # catering specifically to that metric.
        #
        # - `metric_settings` specifies configuration parameters for this metric 
        #   specifically. These may or may not be necessary, depending on each specific
        #   store and metric. The most obvious example of this is for gauges in 
        #   multi-process environments, where the developer needs to choose how those 
        #   gauges will get aggregated between all the per-process values.
        # 
        #   The settings that the store will accept, and what it will do with them, are
        #   100% Store-specific. Each store should document what settings it will accept
        #   and how to use them, so the developer using that store can pass the appropriate 
        #   instantiating the Store itself, and the Metrics they declare.
        #
        # - `metric_type` is specified in case a store wants to validate that the settings
        #   are valid for the metric being set up. It may go unused by most Stores
        #
        # Even if your store doesn't need these two parameters, the Store must expose them
        # to make them swappable.   
        def for_metric(metric_name, metric_type:, metric_settings: {})
          # Generally, here a Store would validate that the settings passed in are valid,
          # and raise if they aren't.
          validate_metric_settings(metric_type: metric_type, 
                                   metric_settings: metric_settings)
          MetricStore.new(store: self, 
                          metric_name: metric_name, 
                          metric_type: metric_type, 
                          metric_settings: metric_settings)
        end

        
        # MetricStore manages the data for one specific metric. It's generally a view onto
        # the central store shared by all metrics, but it could also hold the data itself
        # if that's better for the specific scenario 
        class MetricStore
          # This constructor is internal to this store, so the signature doesn't need to
          # be this. No one other than the Store should be creating MetricStores 
          def initialize(store:, metric_name:, metric_type:, metric_settings:)
          end

          # Metrics may need to modify multiple values at once (Histograms do this, for 
          # example). MetricStore needs to provide a way to synchronize those, in addition
          # to all of the value modifications being thread-safe without a need for simple 
          # Metrics to call `synchronize`
          def synchronize
            raise NotImplementedError
          end

          # Store a value for this metric and a set of labels
          # Internally, may add extra "labels" to disambiguate values between,
          # for example, different processes
          def set(labels:, val:)
            raise NotImplementedError
          end

          def increment(labels:, by: 1)
            raise NotImplementedError
          end
  
          # Return a value for a set of labels
          # Will return the same value stored by `set`, as opposed to `all_values`, which 
          # may aggregate multiple values.
          #
          # For example, in a multi-process scenario, `set` may add an extra internal
          # label tagging the value with the process id. `get` will return the value for
          # "this" process ID. `all_values` will return an aggregated value for all 
          # process IDs.
          def get(labels:)
            raise NotImplementedError
          end
  
          # Returns all the sets of labels seen by the Store, and the aggregated value for 
          # each.
          # 
          # In some cases, this is just a matter of returning the stored value.
          # 
          # In other cases, the store may need to aggregate multiple values for the same
          # set of labels. For example, in a multiple process it may need to `sum` the
          # values of counters from each process. Or for `gauges`, it may need to take the
          # `max`. This is generally specified in `metric_settings` when calling 
          # `Store#for_metric`.
          def all_values
            raise NotImplementedError
          end
        end
      end
    end
  end
end
```

## Conventions

- Your store MAY require or accept extra settings for each metric on the call to `for_metric`.
- You SHOULD validate these parameters to make sure they are correct, and raise if they aren't. 
- If your store needs to aggregate multiple values for the same metric (for example, in
  a multi-process scenario), you MUST accept a setting to define how values are aggregated.
  - This setting MUST be called `:aggregation`
  - It MUST support, at least, `:sum`, `:max` and `:min`. 
  - It MAY support other aggregation modes that may apply to your requirements.
  - It MUST default to `:sum`

## Testing your Store

In order to make it easier to test your store, the basic functionality is tested using
`shared_examples`:

`it_behaves_like Prometheus::Client::DataStores`

Follow the simple structure in `synchronized_spec.rb` for a starting point.

Note that if your store stores data somewhere other than in-memory (in files, Redis, 
databases, etc), you will need to do cleanup between tests in a `before` block.

The tests for `DirectFileStore` have a good example at the top of the file. This file also
has some examples on testing multi-process stores, checking that aggregation between 
processes works correctly.

## Benchmarking your custom data store

If you are developing your own data store, you probably want to benchmark it to see how
it compares to the built-in ones, and to make sure it achieves the performance you want.

The Prometheus Ruby Client includes some benchmarks (in the `spec/benchmarks` directory)
to help you with this, and also with validating that your store works correctly.

The `README` in that directory contains more information what these benchmarks are for,
and how to use them.

## Extra Stores and Research

In the process of abstracting stores away, and creating the built-in ones, GoCardless
has created a good amount of research, benchmarks, and experimental stores, which 
weren't useful to include in this repo, but may be a useful resource or starting point 
if you are building your own store.

Check out the [GoCardless Data Stores Experiments](https://github.com/gocardless/prometheus-client-ruby-data-stores-experiments) 
repository for these.

## Sample, imaginary multi-process Data Store

This is just an example of how one could implement a data store, and a clarification on
the "aggregation" point 

Important: This is a **toy example**, intended simply to show how this could work / how to
implement these interfaces.

There are some key pieces of code missing, which are fairly uninteresting, this only shows
the parts that illustrate the idea of storing multiple different values, and aggregating
them

```ruby
module Prometheus
  module Client
    module DataStores
      # Stores all the data in a magic data structure that keeps cross-process data, in a
      # way that all processes can read it, but each can write only to their own set of
      # keys.
      # It doesn't care how that works, this is not an actual solution to anything,
      # just an example of how the interface would work with something like that.
      #
      # Metric Settings have one possible key, `aggregation`, which must be one of
      # `AGGREGATION_MODES`
      class SampleMagicMultiprocessStore
        AGGREGATION_MODES = [MAX = :max, MIN = :min, SUM = :sum]
        DEFAULT_METRIC_SETTINGS = { aggregation: SUM }

        def initialize
          @internal_store = MagicHashSharedBetweenProcesses.new # PStore, for example
        end

        def for_metric(metric_name, metric_type:, metric_settings: {})
          settings = DEFAULT_METRIC_SETTINGS.merge(metric_settings)
          validate_metric_settings(metric_settings: settings)
          MetricStore.new(store: self,
                          metric_name: metric_name,
                          metric_type: metric_type,
                          metric_settings: settings)
        end

        private

        def validate_metric_settings(metric_settings:)
          raise unless metric_settings.has_key?(:aggregation)
          raise unless metric_settings[:aggregation].in?(AGGREGATION_MODES)
        end

        class MetricStore
          def initialize(store:, metric_name:, metric_type:, metric_settings:)
            @store = store
            @internal_store = store.internal_store
            @metric_name = metric_name
            @aggregation_mode = metric_settings[:aggregation]
          end

          def set(labels:, val:)
            @internal_store[store_key(labels)] = val.to_f
          end

          def get(labels:)
            @internal_store[store_key(labels)]
          end

          def all_values
            non_aggregated_values = all_store_values.each_with_object({}) do |(labels, v), acc|
              if labels["__metric_name"] == @metric_name
                label_set = labels.reject { |k,_| k.in?("__metric_name", "__pid") }
                acc[label_set] ||= []
                acc[label_set] << v
              end
            end

            # Aggregate all the different values for each label_set
            non_aggregated_values.each_with_object({}) do |(label_set, values), acc|
              acc[label_set] = aggregate(values)
            end
          end

          private

          def all_store_values
            # This assumes there's a something common that all processes can write to, and
            # it's magically synchronized (which is not true of a PStore, for example, but
            # would of some sort of external data store like Redis, Memcached, SQLite)

            # This could also have some sort of:
            #    file_list = Dir.glob(File.join(path, '*.db')).sort
            # which reads all the PStore files / MMapped files, etc, and returns a hash
            # with all of them together, which then `values` and `label_sets` can use
          end

          # This method holds most of the key to how this Store works. Adding `_pid` as
          # one of the labels, we hold each process's value separately, which we can 
          # aggregate later 
          def store_key(labels)
            labels.merge(
              {
                "__metric_name" => @metric_name,
                "__pid" => Process.pid
              }
            )
          end

          def aggregate(values)
            # This is a horrible way to do this, just illustrating the point
            values.send(@aggregation_mode)
          end
        end
      end
    end
  end
end
```
