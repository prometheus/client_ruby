# encoding: UTF-8

module Prometheus
  module Client
    # LabelSetValidator ensures that all used label sets comply with the
    # Prometheus specification.
    class LabelSetValidator
      BASE_RESERVED_LABELS = [:pid].freeze
      LABEL_NAME_REGEX = /\A[a-zA-Z_][a-zA-Z0-9_]*\Z/

      class LabelSetError < StandardError; end
      class InvalidLabelSetError < LabelSetError; end
      class InvalidLabelError < LabelSetError; end
      class ReservedLabelError < LabelSetError; end

      attr_reader :expected_labels, :reserved_labels

      def initialize(expected_labels:, reserved_labels: [])
        @expected_labels = expected_labels.sort
        @reserved_labels = BASE_RESERVED_LABELS + reserved_labels
      end

      def validate_symbols!(labels)
        unless labels.respond_to?(:all?)
          raise InvalidLabelSetError, "#{labels} is not a valid label set"
        end

        labels.all? do |key, _|
          validate_symbol(key)
          validate_name(key)
          validate_reserved_key(key)
        end
      end

      def validate_labelset!(labelset)
        begin
          return labelset if keys_match?(labelset)
        rescue ArgumentError
          # If labelset contains keys that are a mixture of strings and symbols, this will
          # raise when trying to sort them, but the error should be the same:
          # InvalidLabelSetError
        end

        raise InvalidLabelSetError, "labels must have the same signature " \
                                    "(keys given: #{labelset.keys} vs." \
                                    " keys expected: #{expected_labels}"
      end

      private

      def keys_match?(labelset)
        labelset.keys.sort == expected_labels
      end

      def validate_symbol(key)
        return true if key.is_a?(Symbol)

        raise InvalidLabelError, "label #{key} is not a symbol"
      end

      def validate_name(key)
        if key.to_s.start_with?('__')
          raise ReservedLabelError, "label #{key} must not start with __"
        end

        unless key.to_s =~ LABEL_NAME_REGEX
          raise InvalidLabelError, "label name must match /#{LABEL_NAME_REGEX}/"
        end

        true
      end

      def validate_reserved_key(key)
        return true unless reserved_labels.include?(key)

        raise ReservedLabelError, "#{key} is reserved"
      end
    end
  end
end
