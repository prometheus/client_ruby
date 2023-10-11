# encoding: UTF-8

require 'base64'
require 'thread'
require 'net/http'
require 'uri'
require 'erb'
require 'set'

require 'prometheus/client'
require 'prometheus/client/formats/text'
require 'prometheus/client/label_set_validator'

module Prometheus
  # Client is a ruby implementation for a Prometheus compatible client.
  module Client
    # Push implements a simple way to transmit a given registry to a given
    # Pushgateway.
    class Push
      class HttpError < StandardError; end
      class HttpRedirectError < HttpError; end
      class HttpClientError < HttpError; end
      class HttpServerError < HttpError; end

      DEFAULT_GATEWAY = 'http://localhost:9091'.freeze
      PATH = '/metrics'.freeze
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
        validate_no_basic_auth!(@uri)

        @http = Net::HTTP.new(@uri.host, @uri.port)
        @http.use_ssl = (@uri.scheme == 'https')
        @http.open_timeout = kwargs[:open_timeout] if kwargs[:open_timeout]
        @http.read_timeout = kwargs[:read_timeout] if kwargs[:read_timeout]
      end

      def basic_auth(user, password)
        @user = user
        @password = password
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
        job = job.to_s

        # Job can't be empty, but it can contain `/`, so we need to base64
        # encode it in that case
        if job.include?('/')
          encoded_job = Base64.urlsafe_encode64(job)
          path = "#{PATH}/job@base64/#{encoded_job}"
        else
          path = "#{PATH}/job/#{ERB::Util::url_encode(job)}"
        end

        grouping_key.each do |label, value|
          value = value.to_s

          if value.include?('/')
            encoded_value = Base64.urlsafe_encode64(value)
            path += "/#{label}@base64/#{encoded_value}"
          # While it's valid for the urlsafe_encode64 function to return an
          # empty string when the input string is empty, it doesn't work for
          # our specific use case as we're putting the result into a URL path
          # segment. A double slash (`//`) can be normalised away by HTTP
          # libraries, proxies, and web servers.
          #
          # For empty strings, we use a single padding character (`=`) as the
          # value.
          #
          # See the pushgateway docs for more details:
          #
          # https://github.com/prometheus/pushgateway/blob/6393a901f56d4dda62cd0f6ab1f1f07c495b6354/README.md#url
          elsif value.empty?
            path += "/#{label}@base64/="
          else
            path += "/#{label}/#{ERB::Util::url_encode(value)}"
          end
        end

        path
      end

      def request(req_class, registry = nil)
        validate_no_label_clashes!(registry) if registry

        req = req_class.new(@uri)
        req.content_type = Formats::Text::CONTENT_TYPE
        req.basic_auth(@user, @password) if @user
        req.body = Formats::Text.marshal(registry) if registry

        response = @http.request(req)
        validate_response!(response)

        response
      end

      def synchronize
        @mutex.synchronize { yield }
      end

      def validate_no_basic_auth!(uri)
        if uri.user || uri.password
          raise ArgumentError, <<~EOF
            Setting Basic Auth credentials in the gateway URL is not supported, please call the `basic_auth` method.

            Received username `#{uri.user}` in gateway URL. Instead of passing
            Basic Auth credentials like this:

            ```
            push = Prometheus::Client::Push.new(job: "my-job", gateway: "http://user:password@localhost:9091")
            ```

            please pass them like this:

            ```
            push = Prometheus::Client::Push.new(job: "my-job", gateway: "http://localhost:9091")
            push.basic_auth("user", "password")
            ```

            While URLs do support passing Basic Auth credentials using the
            `http://user:password@example.com/` syntax, the username and
            password in that syntax have to follow the usual rules for URL
            encoding of characters per RFC 3986
            (https://datatracker.ietf.org/doc/html/rfc3986#section-2.1).

            Rather than place the burden of correctly performing that encoding
            on users of this gem, we decided to have a separate method for
            supplying Basic Auth credentials, with no requirement to URL encode
            the characters in them.
          EOF
        end
      end

      def validate_no_label_clashes!(registry)
        # There's nothing to check if we don't have a grouping key
        return if @grouping_key.empty?

        # We could be doing a lot of comparisons, so let's do them against a
        # set rather than an array
        grouping_key_labels = @grouping_key.keys.to_set

        registry.metrics.each do |metric|
          metric.labels.each do |label|
            if grouping_key_labels.include?(label)
              raise LabelSetValidator::InvalidLabelSetError,
                "label :#{label} from grouping key collides with label of the " \
                "same name from metric :#{metric.name} and would overwrite it"
            end
          end
        end
      end

      def validate_response!(response)
        status = Integer(response.code)
        if status >= 300
          message = "status: #{response.code}, message: #{response.message}, body: #{response.body}"
          if status <= 399
            raise HttpRedirectError, message
          elsif status <= 499
            raise HttpClientError, message
          else
            raise HttpServerError, message
          end
        end
      end
    end
  end
end
