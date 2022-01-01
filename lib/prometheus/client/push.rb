# encoding: UTF-8

require 'thread'
require 'net/http'
require 'uri'
require 'erb'

require 'prometheus/client'
require 'prometheus/client/formats/text'
require 'prometheus/client/label_set_validator'

module Prometheus
  # Client is a ruby implementation for a Prometheus compatible client.
  module Client
    # Push implements a simple way to transmit a given registry to a given
    # Pushgateway.
    class Push
      DEFAULT_GATEWAY = 'http://localhost:9091'.freeze
      PATH            = '/metrics/job/%s'.freeze
      SUPPORTED_SCHEMES = %w(http https).freeze

      attr_reader :job, :gateway, :path

      def initialize(job:, gateway: DEFAULT_GATEWAY, grouping_key: {}, **kwargs)
        raise ArgumentError, "job cannot be nil" if job.nil?
        raise ArgumentError, "job cannot be empty" if job.empty?
        @validator = LabelSetValidator.new(expected_labels: grouping_key.keys)
        @validator.validate_symbols!(grouping_key)

        @mutex = Mutex.new
        @job = job
        @gateway = gateway || DEFAULT_GATEWAY
        @grouping_key = grouping_key
        @path = build_path(job, grouping_key)
        @uri = parse("#{@gateway}#{@path}")

        @http = Net::HTTP.new(@uri.host, @uri.port)
        @http.use_ssl = (@uri.scheme == 'https')
        @http.open_timeout = kwargs[:open_timeout] if kwargs[:open_timeout]
        @http.read_timeout = kwargs[:read_timeout] if kwargs[:read_timeout]
      end

      def add(registry)
        synchronize do
          request(Net::HTTP::Post, registry)
        end
      end

      def replace(registry)
        synchronize do
          request(Net::HTTP::Put, registry)
        end
      end

      def delete
        synchronize do
          request(Net::HTTP::Delete)
        end
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

      def build_path(job, grouping_key)
        path = format(PATH, ERB::Util::url_encode(job))

        grouping_key.each do |label, value|
          path += "/#{label}/#{ERB::Util::url_encode(value)}"
        end

        path
      end

      def request(req_class, registry = nil)
        req = req_class.new(@uri)
        req.content_type = Formats::Text::CONTENT_TYPE
        req.basic_auth(@uri.user, @uri.password) if @uri.user
        req.body = Formats::Text.marshal(registry) if registry

        @http.request(req)
      end

      def synchronize
        @mutex.synchronize { yield }
      end
    end
  end
end
