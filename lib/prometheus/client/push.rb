# encoding: UTF-8

require 'net/http'
require 'uri'

require 'prometheus/client'
require 'prometheus/client/formats/text'

module Prometheus
  # Client is a ruby implementation for a Prometheus compatible client.
  module Client
    # Push implements a simple way to transmit a given registry to a given
    # Pushgateway.
    class Push
      DEFAULT_GATEWAY = 'http://localhost:9091'.freeze
      PATH            = '/metrics/jobs/%s'.freeze
      INSTANCE_PATH   = '/metrics/jobs/%s/instances/%s'.freeze
      HEADER          = { 'Content-Type' => Formats::Text::CONTENT_TYPE }.freeze
      SUPPORTED_SCHEMES = %w(http https).freeze

      attr_reader :job, :instance, :gateway, :path

      def initialize(job, instance = nil, gateway = nil)
        @job = job
        @instance = instance
        @gateway = gateway || DEFAULT_GATEWAY
        @uri = parse(@gateway)
        @path = build_path(job, instance)
        @http = Net::HTTP.new(@uri.host, @uri.port)
        @http.use_ssl = @uri.scheme == 'https'
      end

      def add(registry)
        request('POST', registry)
      end

      def replace(registry)
        request('PUT', registry)
      end

      def delete
        @http.send_request('DELETE', path)
      end

      private

      def parse(url)
        uri = URI.parse(url)

        unless SUPPORTED_SCHEMES.include?(uri.scheme)
          raise ArgumentError, 'only HTTP gateway URLs are supported currently.'
        end

        uri
      rescue URI::InvalidURIError => e
        raise ArgumentError, "#{url} is not a valid URL: #{e}"
      end

      def build_path(job, instance)
        if instance
          format(INSTANCE_PATH, URI.escape(job), URI.escape(instance))
        else
          format(PATH, URI.escape(job))
        end
      end

      def request(method, registry)
        data = Formats::Text.marshal(registry)

        @http.send_request(method, path, data, HEADER)
      end
    end
  end
end
