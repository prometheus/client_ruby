require 'prometheus/client'

module Prometheus
  module Client
    module Rack
      class Collector
        attr_reader :app, :registry

        def initialize(app, options = {})
          @app = app
          @registry = options[:registry] || Client.registry

          init_metrics
        end

        def call(env) # :nodoc:
          start = Time.now
          @app.call(env)
        ensure
          @requests.increment
          @requests_duration.increment({}, ((Time.now - start) * 1_000_000).to_i)
        end

      protected

        def init_metrics
          @requests = @registry.counter(:http_requests_total, 'A counter of the total number of HTTP requests made')
          @requests_duration = @registry.counter(:http_request_durations_total_microseconds, 'The total amount of time Rack has spent answering HTTP requests (microseconds).')
        end

      end
    end
  end
end
