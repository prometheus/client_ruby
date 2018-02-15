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
    # By default metrics all have the prefix "http_server". Set to something
    # else if you like.
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
        @metrics_prefix = options[:metrics_prefix] || 'http_server'
        @counter_lb = options[:counter_label_builder] || COUNTER_LB
        @duration_lb = options[:duration_label_builder] || DURATION_LB

        init_request_metrics
        init_exception_metrics
      end

      def call(env) # :nodoc:
        trace(env) { @app.call(env) }
      end

      protected

      aggregation = lambda do |str|
        str
          .gsub(%r{/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(/|$)}, '/:uuid\\1')
          .gsub(%r{/\d+(/|$)}, '/:id\\1')
      end

      COUNTER_LB = proc do |env, code|
        {
          code:   code,
          method: env['REQUEST_METHOD'].downcase,
          path:   aggregation.call(env['PATH_INFO']),
        }
      end

      DURATION_LB = proc do |env, _|
        {
          method: env['REQUEST_METHOD'].downcase,
          path:   aggregation.call(env['PATH_INFO']),
        }
      end

      def init_request_metrics
        @requests = @registry.counter(
          :"#{@metrics_prefix}_requests_total",
          'The total number of HTTP requests handled by the Rack application.',
        )
        @durations = @registry.histogram(
          :"#{@metrics_prefix}_request_duration_seconds",
          'The HTTP response duration of the Rack application.',
        )
      end

      def init_exception_metrics
        @exceptions = @registry.counter(
          :"#{@metrics_prefix}_exceptions_total",
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
