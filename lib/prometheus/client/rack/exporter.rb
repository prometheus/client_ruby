require 'prometheus/client'

module Prometheus
  module Client
    module Rack
      class Exporter
        attr_reader :app, :registry, :path

        def initialize(app, options = {})
          @app = app
          @registry = options[:registry] || Client.registry
          @path = options[:path] || '/metrics.json'
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
          json = @registry.to_json
          headers = {
            'Content-Type' => 'application/json',
            'Content-Length' => json.size.to_s
          }

          [200, headers, [json]]
        end

      end
    end
  end
end
