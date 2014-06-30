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
          @label_builder = label_builder || proc do |env|
            {
              method: env['REQUEST_METHOD'].downcase,
              path:   env['PATH_INFO'].to_s,
            }
          end

          init_request_metrics
          init_exception_metrics
        end

        def call(env) # :nodoc:
          trace(env) { @app.call(env) }
        end

        protected

        def init_request_metrics
          @requests = @registry.counter(
            :http_requests_total,
            'A counter of the total number of HTTP requests made.')
          @requests_duration = @registry.counter(
            :http_request_durations_total_microseconds,
            'The total amount of time spent answering HTTP requests ' \
            '(microseconds).')
          @durations = @registry.summary(
            :http_request_durations_microseconds,
            'A histogram of the response latency (microseconds).')
        end

        def init_exception_metrics
          @exceptions = @registry.counter(
            :http_exceptions_total,
            'A counter of the total number of exceptions raised.')
        end

        def trace(env)
          start = Time.now
          yield.tap do |response|
            duration = ((Time.now - start) * 1_000_000).to_i
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
          @requests_duration.increment(labels, duration)
          @durations.add(labels, duration)
        rescue
          # TODO: log unexpected exception during request recording
          nil
        end
      end
    end
  end
end
