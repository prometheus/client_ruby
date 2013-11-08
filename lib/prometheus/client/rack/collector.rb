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
          execution_time = ((Time.now - start) * 1_000_000).to_i
          label_set = { :method => env['REQUEST_METHOD'] }
          @requests.increment(label_set)
          @requests_duration.increment(label_set, execution_time)
          @latency.add(label_set, execution_time)
        end

      protected

        def init_metrics
          @requests = @registry.counter(:http_requests_total, 'A counter of the total number of HTTP requests made')
          @requests_duration = @registry.counter(:http_request_durations_total_microseconds, 'The total amount of time Rack has spent answering HTTP requests (microseconds).')
          @latency = @registry.summary(:http_request_latency_microseconds, 'A histogram of the response latency for requests made (microseconds).')
        end

      end
    end
  end
end
