# encoding: UTF-8

require 'benchmark'
require 'prometheus/client'

module Prometheus
  module Middleware
    # Collector is a Rack middleware that provides a sample implementation of a
    # HTTP tracer.
    #
    # By default metrics are registered on the global registry. Set the
    # `:registry` option to use a custom registry.
    #
    # By default metrics all have the prefix "http_server". Set
    # `:metrics_prefix` to something else if you like.
    #
    # The request counter metric is broken down by code, method and path.
    # The request duration metric is broken down by method and path.
    class Collector
      attr_reader :app, :registry

      def initialize(app, options = {})
        @app = app
        @registry = options[:registry] || Client.registry
        @metrics_prefix = options[:metrics_prefix] || 'http_server'

        init_request_metrics
        init_exception_metrics
      end

      def call(env) # :nodoc:
        trace(env) { @app.call(env) }
      end

      protected

      def init_request_metrics
        @requests = @registry.counter(
          :"#{@metrics_prefix}_requests_total",
          docstring:
            'The total number of HTTP requests handled by the Rack application.',
          labels: %i[code method path]
        )
        @durations = @registry.histogram(
          :"#{@metrics_prefix}_request_duration_seconds",
          docstring: 'The HTTP response duration of the Rack application.',
          labels: %i[method path]
        )
      end

      def init_exception_metrics
        @exceptions = @registry.counter(
          :"#{@metrics_prefix}_exceptions_total",
          docstring: 'The total number of exceptions raised by the Rack application.',
          labels: [:exception]
        )
      end

      def trace(env)
        response = nil
        duration = Benchmark.realtime { response = yield }
        record(env, response.first.to_s, duration)
        return response
      rescue => exception
        @exceptions.increment(labels: { exception: exception.class.name })
        raise
      end

      def record(env, code, duration)
        path = generate_path(env)

        counter_labels = {
          code:   code,
          method: env['REQUEST_METHOD'].downcase,
          path:   strip_ids_from_path(path),
        }

        duration_labels = {
          method: env['REQUEST_METHOD'].downcase,
          path:   strip_ids_from_path(path),
        }

        @requests.increment(labels: counter_labels)
        @durations.observe(duration, labels: duration_labels)
      rescue
        # TODO: log unexpected exception during request recording
        nil
      end

      # While `PATH_INFO` is framework agnostic, and works for any Rack app, some Ruby web
      # frameworks pass a more useful piece of information into the request env - the
      # route that the request matched.
      #
      # This means that rather than using our generic `:id` and `:uuid` replacements in
      # the `path` label for any path segments that look like dynamic IDs, we can put the
      # actual route that matched in there, with correctly named parameters. For example,
      # if a Sinatra app defined a route like:
      #
      # get "/foo/:bar" do
      #   ...
      # end
      #
      # instead of containing `/foo/:id`, the `path` label would contain `/foo/:bar`.
      #
      # Sadly, Rails is a notable exception, and (as far as I can tell at the time of
      # writing) doesn't provide this info in the request env.
      def generate_path(env)
        if env['sinatra.route']
          route = env['sinatra.route'].partition(' ').last
        elsif env['grape.routing_args']
          # We are deep in the weeds of an object that Grape passes into the request env,
          # but don't document any explicit guarantees about. Let's have a fallback in
          # case they change it down the line.
          #
          # This code would be neater with the safe navigation operator (`&.`) here rather
          # than the much more verbose `respond_to?` calls, but unlike Rails' `try`
          # method, it still raises an error if the object is non-nil, but doesn't respond
          # to the method being called on it.
          route = nil

          route_info = env.dig('grape.routing_args', :route_info)
          if route_info.respond_to?(:pattern)
            pattern = route_info.pattern
            if pattern.respond_to?(:origin)
              route = pattern.origin
            end
          end

          # Fall back to PATH_INFO if Grape change the structure of `grape.routing_args`
          route ||= env['PATH_INFO']
        else
          route = env['PATH_INFO']
        end

        [env['SCRIPT_NAME'], route].join
      end

      def strip_ids_from_path(path)
        path
          .gsub(%r{/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(/|$)}, '/:uuid\\1')
          .gsub(%r{/\d+(/|$)}, '/:id\\1')
      end
    end
  end
end
