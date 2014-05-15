# encoding: UTF-8

require 'prometheus/client'
require 'prometheus/client/formats/json'

module Prometheus
  module Client
    module Rack
      # Exporter is a Rack middleware that provides a sample implementation of
      # a HTTP tracer. The default label builder can be modified to export a
      # differet set of labels per recorded metric.
      class Exporter
        attr_reader :app, :registry, :path

        def initialize(app, options = {})
          @app = app
          @registry = options[:registry] || Client.registry
          @path = options[:path] || '/metrics'
        end

        def call(env)
          if env['PATH_INFO'] == @path
            response(Formats::JSON)
          else
            @app.call(env)
          end
        end

        protected

        def response(format)
          [
            200,
            { 'Content-Type' => format::TYPE },
            [format.marshal(@registry)],
          ]
        end
      end
    end
  end
end
