# encoding: UTF-8

require 'prometheus/client'

module Prometheus
  module Client
    module Rack
      # Collector is a Rack middleware that provides a sample implementation of
      # a HTTP tracer. The default label builder can be modified to export a
      # different set of labels per recorded metric.
      class Collector
        attr_reader :app, :registry

        def initialize(app, options = {}, &label_builder)
          @app = app
          @registry = options[:registry] || Client.registry
          @label_builder = label_builder || DEFAULT_LABEL_BUILDER

          init_request_metrics
          init_exception_metrics
        end

        def call(env) # :nodoc:
          trace(env) { @app.call(env) }
        end

        protected

        DEFAULT_LABEL_BUILDER = proc do |env|
          {
            method: env['REQUEST_METHOD'].downcase,
            host:   env['HTTP_HOST'].to_s,
            path:   env['PATH_INFO'].to_s,
          }
        end

        def init_request_metrics
          @requests = @registry.counter(
            :http_requests_total,
            'A counter of the total number of HTTP requests made.',
          )
          @durations = @registry.summary(
            :http_request_duration_seconds,
            'A histogram of the response latency.',
          )
        end

        def init_exception_metrics
          @exceptions = @registry.counter(
            :http_exceptions_total,
            'A counter of the total number of exceptions raised.',
          )
        end

        def trace(env)
          start = Time.now
          yield.tap do |response|
            duration = (Time.now - start).to_f
            record(labels(env, response), duration)
          end
        rescue => exception
          @exceptions.increment(exception: exception.class.name)
          raise
        end

        def labels(env, response)
          @label_builder.call(env).tap do |labels|
            labels[:code] = response.first.to_s
          end
        end

        def record(labels, duration)
          @requests.increment(labels)
          @durations.observe(labels, duration)
        rescue
          # TODO: log unexpected exception during request recording
          nil
        end
      end
    end
  end
end
