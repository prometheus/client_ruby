# encoding: UTF-8

require 'prometheus/client'

module Prometheus
  module Middleware
    # Collector is a Rack middleware that provides a sample implementation of a
    # HTTP tracer.
    #
    # By default metrics are registered on the global registry. Set the
    # `:registry` option to use a custom registry.
    #
    # The request counter metric is broken down by code, method and path by
    # default. Set the `:counter_label_builder` option to use a custom label
    # builder.
    #
    # The request duration metric is broken down by method and path by default.
    # Set the `:duration_label_builder` option to use a custom label builder.
    class Collector
      attr_reader :app, :registry

      def initialize(app, options = {})
        @app = app
        @registry = options[:registry] || Client.registry
        @counter_lb = options[:counter_label_builder] || COUNTER_LB
        @duration_lb = options[:duration_label_builder] || DURATION_LB

        init_request_metrics
        init_exception_metrics
      end

      def call(env) # :nodoc:
        trace(env) { @app.call(env) }
      end

      protected

      COUNTER_LB = proc do |env, code|
        {
          code:   code,
          method: env['REQUEST_METHOD'].downcase,
          path:   env['PATH_INFO'].to_s,
        }
      end

      DURATION_LB = proc do |env, _|
        {
          method: env['REQUEST_METHOD'].downcase,
          path:   env['PATH_INFO'].to_s,
        }
      end

      def init_request_metrics
        @requests = @registry.counter(
          :http_server_requests_total,
          'The total number of HTTP requests handled by the Rack application.',
        )
        @durations = @registry.histogram(
          :http_server_request_duration_seconds,
          'The HTTP response duration of the Rack application.',
        )
      end

      def init_exception_metrics
        @exceptions = @registry.counter(
          :http_server_exceptions_total,
          'The total number of exceptions raised by the Rack application.',
        )
      end

      def trace(env)
        start = Time.now
        yield.tap do |response|
          duration = [(Time.now - start).to_f, 0.0].max
          record(env, response.first.to_s, duration)
        end
      rescue => exception
        @exceptions.increment(exception: exception.class.name)
        raise
      end

      def record(env, code, duration)
        @requests.increment(@counter_lb.call(env, code))
        @durations.observe(@duration_lb.call(env, code), duration)
      rescue
        # TODO: log unexpected exception during request recording
        nil
      end
    end
  end
end
