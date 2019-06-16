# encoding: UTF-8

require 'prometheus/client'

module Prometheus
  module Middleware
    # This class integrates with a Prometheus::Client::Tracer to update associated metric
    # traces just prior to serving metrics. By default, this will collect traces on the
    # global Client tracer.
    class TraceCollector
      def initialize(app, options = {})
        @app = app
        @tracer = options[:tracer] || Client.tracer
      end

      def call(env)
        @tracer.collect
        @app.call(env)
      end
    end
  end
end
