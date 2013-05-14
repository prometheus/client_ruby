module Prometheus
  module Client
    # LabelSet is a pseudo class used to ensure given labels are semantically
    # correct.
    class LabelSet
      # TODO: we might allow setting :instance in the future
      RESERVED_LABELS = [:name, :job, :instance]

      class LabelSetError        < StandardError; end
      class InvalidLabelSetError < LabelSetError; end
      class InvalidLabelError    < LabelSetError; end
      class ReservedLabelError   < LabelSetError; end

      # A list of validated label sets
      @@validated = {}

      def self.new(labels)
        validate(labels)
        labels
      end

    protected

      def self.validate(labels)
        @@validated[labels.hash] ||= begin
          labels.keys.each do |key|
            unless Symbol === key
              raise InvalidLabelError, "label name #{key} is not a symbol"
            end

            if RESERVED_LABELS.include?(key)
              raise ReservedLabelError, "labels may not contain reserved #{key} label"
            end
          end

          true
        end
      rescue NoMethodError
        raise InvalidLabelSetError, "#{labels} is not a valid label set"
      end

    end
  end
end
