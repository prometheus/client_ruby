# encoding: UTF-8

module Prometheus
  module Client
    # LabelSetValidator ensures that all used label sets comply with the
    # Prometheus specification.
    class LabelSetValidator
      # TODO: we might allow setting :instance in the future
      BASE_RESERVED_LABELS = [:job, :instance].freeze

      class LabelSetError < StandardError; end
      class InvalidLabelSetError < LabelSetError; end
      class InvalidLabelError < LabelSetError; end
      class ReservedLabelError < LabelSetError; end

      attr_reader :expected_labels, :reserved_labels

      def initialize(expected_labels:, reserved_labels: [])
        @expected_labels = expected_labels.sort
        @reserved_labels = BASE_RESERVED_LABELS + reserved_labels
        @validated = {}
      end

      def valid?(labels)
        unless labels.respond_to?(:all?)
          raise InvalidLabelSetError, "#{labels} is not a valid label set"
        end

        labels.all? do |key, _|
          validate_symbol(key)
          validate_name(key)
          validate_reserved_key(key)
        end
      end

      def validate(labels)
        return labels if @validated.key?(labels.hash)

        valid?(labels)

        unless keys_match?(labels)
          raise InvalidLabelSetError, "labels must have the same signature " \
                                      "(keys given: #{labels.keys.sort} vs." \
                                      " keys expected: #{expected_labels}"
        end

        @validated[labels.hash] = labels
      end

      private

      def keys_match?(labels)
        labels.keys.sort == expected_labels
      end

      def validate_symbol(key)
        return true if key.is_a?(Symbol)

        raise InvalidLabelError, "label #{key} is not a symbol"
      end

      def validate_name(key)
        return true unless key.to_s.start_with?('__')

        raise ReservedLabelError, "label #{key} must not start with __"
      end

      def validate_reserved_key(key)
        return true unless reserved_labels.include?(key)

        raise ReservedLabelError, "#{key} is reserved"
      end
    end
  end
end
