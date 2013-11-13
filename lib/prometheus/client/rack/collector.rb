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
          trace(env) { @app.call(env) }
        end

      protected

        def init_metrics
          @requests = @registry.counter(:http_requests_total, 'A counter of the total number of HTTP requests made')
          @requests_duration = @registry.counter(:http_request_durations_total_microseconds, 'The total amount of time Rack has spent answering HTTP requests (microseconds).')
          @durations = @registry.summary(:http_request_durations_microseconds, 'A histogram of the response latency for requests made (microseconds).')
        end

        def trace(env, &block)
          start = Time.now
          response = yield
        rescue => exception
          raise
        ensure
          duration = ((Time.now - start) * 1_000_000).to_i
          record(duration, env, response, exception)
        end

        def record(duration, env, response, exception)
          labels = {
            :method => env['REQUEST_METHOD'].downcase,
            :path   => env['PATH_INFO'].to_s,
          }

          if response
            labels[:code] = response.first.to_s
          else
            labels[:exception] = exception.class.name
          end

          @requests.increment(labels)
          @requests_duration.increment(labels, duration)
          @durations.add(labels, duration)
        rescue => error
          # TODO: log unexpected exception during request recording
        end

      end
    end
  end
end
