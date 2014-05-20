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
      DEFAULT_GATEWAY = 'http://localhost:9091'
      PATH            = '/metrics/jobs/%s'
      INSTANCE_PATH   = '/metrics/jobs/%s/instances/%s'
      HEADER          = { 'Content-Type' => Formats::Text::CONTENT_TYPE }

      attr_reader :job, :instance, :gateway, :path

      def initialize(job, instance = nil, gateway = nil)
        @job, @instance, @gateway = job, instance, gateway || DEFAULT_GATEWAY

        @uri  = parse(@gateway)
        @path = format(instance ? INSTANCE_PATH : PATH, job, instance)
      end

      def push(registry)
        data = Formats::Text.marshal(registry)
        http = Net::HTTP.new(@uri.host, @uri.port)

        http.send_request('PUT', @path, data, HEADER)
      end

      private

      def parse(url)
        uri = URI.parse(url)

        if uri.scheme == 'http'
          uri
        else
          fail ArgumentError, 'only HTTP gateway URLs are supported currently.'
        end
      rescue URI::InvalidURIError => e
        raise ArgumentError, "#{url} is not a valid URL: #{e}"
      end
    end
  end
end
