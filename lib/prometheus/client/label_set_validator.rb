# encoding: UTF-8

module Prometheus
  module Client
    # LabelSetValidator ensures that all used label sets comply with the
    # Prometheus specification.
    class LabelSetValidator
      # TODO: we might allow setting :instance in the future
      RESERVED_LABELS = [:job, :instance]

      class LabelSetError < StandardError; end
      class InvalidLabelSetError < LabelSetError; end
      class InvalidLabelError < LabelSetError; end
      class ReservedLabelError < LabelSetError; end

      def initialize
        @validated = {}
      end

      def valid?(labels)
        unless labels.respond_to?(:all?)
          fail InvalidLabelSetError, "#{labels} is not a valid label set"
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

        unless @validated.empty? || match?(labels, @validated.first.last)
          fail InvalidLabelSetError, 'labels must have the same signature'
        end

        @validated[labels.hash] = labels
      end

      private

      def match?(a, b)
        a.keys.sort == b.keys.sort
      end

      def validate_symbol(key)
        return true if key.is_a?(Symbol)

        fail InvalidLabelError, "label #{key} is not a symbol"
      end

      def validate_name(key)
        return true unless key.to_s.start_with?('__')

        fail ReservedLabelError, "label #{key} must not start with __"
      end

      def validate_reserved_key(key)
        return true unless RESERVED_LABELS.include?(key)

        fail ReservedLabelError, "#{key} is reserved"
      end
    end
  end
end
