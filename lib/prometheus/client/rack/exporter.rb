# encoding: UTF-8

require 'prometheus/client'
require 'prometheus/client/formats/json'
require 'prometheus/client/formats/text'

module Prometheus
  module Client
    module Rack
      # Exporter is a Rack middleware that provides a sample implementation of
      # a HTTP tracer. The default label builder can be modified to export a
      # differet set of labels per recorded metric.
      class Exporter
        attr_reader :app, :registry, :path

        AVAILABLE = [Formats::Text, Formats::JSON]
        FORMATS   = AVAILABLE.reduce({}) { |a, e| a.merge(e::TYPE => e) }
        FALLBACK  = Formats::JSON

        def initialize(app, options = {})
          @app = app
          @registry = options[:registry] || Client.registry
          @path = options[:path] || '/metrics'
        end

        def call(env)
          if env['PATH_INFO'] == @path
            format = negotiate(env['HTTP_ACCEPT'], FORMATS, FALLBACK)
            respond_with(format)
          else
            @app.call(env)
          end
        end

        private

        def negotiate(accept, formats, fallback)
          parse(accept).each do |content_type, _|
            return formats[content_type] if formats.key?(content_type)
          end

          fallback
        end

        def parse(header)
          header.to_s.split(/\s*,\s*/).map do |type|
            attributes = type.split(/\s*;\s*/)
            quality = 1.0
            attributes.delete_if do |attr|
              quality = attr.split('q=').last.to_f if attr.start_with?('q=')
            end
            [attributes.join('; '), quality]
          end.sort_by(&:last).reverse
        end

        def respond_with(format)
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
