require 'prometheus/client'

module Prometheus
  module Client
    module Rack
      class Exporter
        attr_reader :app, :registry, :path

        API_VERSION  = '0.0.2'
        CONTENT_TYPE = 'application/json; schema="prometheus/telemetry"; version=' + API_VERSION
        HEADERS      = { 'Content-Type' => CONTENT_TYPE }

        def initialize(app, options = {})
          @app = app
          @registry = options[:registry] || Client.registry
          @path = options[:path] || '/metrics'
        end

        def call(env)
          if env['PATH_INFO'] == @path
            metrics_response
          else
            @app.call(env)
          end
        end

      protected

        def metrics_response
          [200, HEADERS, [@registry.to_json]]
        end

      end
    end
  end
end
