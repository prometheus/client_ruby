# encoding: UTF-8

require 'prometheus/client'
require 'prometheus/client/formats/json'
require 'prometheus/client/formats/text'

module Prometheus
  module Client
    module Rack
      # Exporter is a Rack middleware that provides a sample implementation of
      # a Prometheus HTTP client API.
      class Exporter
        attr_reader :app, :registry, :path

        FORMATS  = [Formats::Text, Formats::JSON]
        FALLBACK = Formats::JSON

        def initialize(app, options = {})
          @app = app
          @registry = options[:registry] || Client.registry
          @path = options[:path] || '/metrics'
          @acceptable = build_dictionary(FORMATS, FALLBACK)
        end

        def call(env)
          if env['PATH_INFO'] == @path
            format = negotiate(env['HTTP_ACCEPT'], @acceptable)
            format ? respond_with(format) : not_acceptable(FORMATS)
          else
            @app.call(env)
          end
        end

        private

        def negotiate(accept, formats)
          accept = '*/*' if accept.to_s.empty?

          parse(accept).each do |content_type, _|
            return formats[content_type] if formats.key?(content_type)
          end

          nil
        end

        def parse(header)
          header.to_s.split(/\s*,\s*/).map do |type|
            attributes = type.split(/\s*;\s*/)
            quality = extract_quality(attributes)

            [attributes.join('; '), quality]
          end.sort_by(&:last).reverse
        end

        def extract_quality(attributes, default = 1.0)
          quality = default

          attributes.delete_if do |attr|
            quality = attr.split('q=').last.to_f if attr.start_with?('q=')
          end

          quality
        end

        def respond_with(format)
          [
            200,
            { 'Content-Type' => format::CONTENT_TYPE },
            [format.marshal(@registry)],
          ]
        end

        def not_acceptable(formats)
          types = formats.map { |format| format::MEDIA_TYPE }

          [
            406,
            { 'Content-Type' => 'text/plain' },
            ["Supported media types: #{types.join(', ')}"],
          ]
        end

        def build_dictionary(formats, fallback)
          formats.each_with_object('*/*' => fallback) do |format, memo|
            memo[format::CONTENT_TYPE] = format
            memo[format::MEDIA_TYPE] = format
          end
        end
      end
    end
  end
end
