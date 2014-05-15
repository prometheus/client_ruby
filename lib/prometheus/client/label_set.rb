# encoding: UTF-8

module Prometheus
  module Client
    # LabelSet is a pseudo class used to ensure given labels are semantically
    # correct.
    class LabelSet
      # TODO: we might allow setting :instance in the future
      RESERVED_LABELS = [:job, :instance]

      class LabelSetError        < StandardError; end
      class InvalidLabelSetError < LabelSetError; end
      class InvalidLabelError    < LabelSetError; end
      class ReservedLabelError   < LabelSetError; end

      # A list of validated label sets
      @validated = {}

      def self.new(labels)
        validate(labels)
        labels
      end

      def self.validate(labels)
        @validated[labels.hash] ||= begin
          labels.keys.each do |key|
            validate_symbol(key)
            validate_reserved_key(key)
          end

          true
        end
      rescue NoMethodError
        raise InvalidLabelSetError, "#{labels} is not a valid label set"
      end

      def self.validate_symbol(key)
        unless key.is_a?(Symbol)
          fail InvalidLabelError, "label #{key} is not a symbol"
        end
      end

      def self.validate_reserved_key(key)
        if key.to_s.start_with?('__')
          fail ReservedLabelError, "label #{key} must not start with __"
        end

        if RESERVED_LABELS.include?(key)
          fail ReservedLabelError, "#{key} is reserved"
        end
      end
    end
  end
end
