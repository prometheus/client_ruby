module Prometheus
  module Client
    module DataStores
      # Stores all the data in a simple Hash for each Metric
      #
      # Has *no* synchronization primitives, making it the fastest store for single-threaded
      # scenarios, but must absolutely not be used in multi-threaded scenarios.
      class SingleThreaded
        class InvalidStoreSettingsError < StandardError; end

        def for_metric(metric_name, metric_type:, metric_settings: {})
          # We don't need `metric_type` or `metric_settings` for this particular store
          validate_metric_settings(metric_settings: metric_settings)
          MetricStore.new
        end

        private

        def validate_metric_settings(metric_settings:)
          unless metric_settings.empty?
            raise InvalidStoreSettingsError,
                  "SingleThreaded doesn't allow any metric_settings"
          end
        end

        class MetricStore
          def initialize
            @internal_store = Hash.new { |hash, key| hash[key] = 0.0 }
          end

          def synchronize
            yield
          end

          def set(labels:, val:)
            @internal_store[labels] = val.to_f
          end

          def increment(labels:, by: 1)
            @internal_store[labels] += by
          end

          def get(labels:)
            @internal_store[labels]
          end

          def all_values
            @internal_store.dup
          end
        end

        private_constant :MetricStore
      end
    end
  end
end
