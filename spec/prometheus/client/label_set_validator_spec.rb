# frozen_string_literal: true

require "prometheus/client/label_set_validator"

describe Prometheus::Client::LabelSetValidator do
  let(:expected_labels) { [] }
  let(:validator) { Prometheus::Client::LabelSetValidator.new(expected_labels: expected_labels) }
  let(:invalid) { Prometheus::Client::LabelSetValidator::InvalidLabelSetError }

  describe ".new" do
    it "returns an instance of a LabelSetValidator" do
      expect(validator).to be_a(Prometheus::Client::LabelSetValidator)
    end
  end

  describe "#validate_symbols!" do
    it "returns true for a valid label check" do
      expect(validator.validate_symbols!(version: "alpha")).to be(true)
    end

    it "raises Invaliddescribed_classError if a label set is not a hash" do
      expect do
        validator.validate_symbols!("invalid")
      end.to raise_exception invalid
    end

    it "raises InvalidLabelError if a label key is not a symbol" do
      expect do
        validator.validate_symbols!("key" => "value")
      end.to raise_exception(described_class::InvalidLabelError)
    end

    it "raises InvalidLabelError if a label key starts with __" do
      expect do
        validator.validate_symbols!(__reserved__: "key")
      end.to raise_exception(described_class::ReservedLabelError)
    end

    it "raises ReservedLabelError if a label key is reserved" do
      %i[job instance pid].each do |label|
        expect do
          validator.validate_symbols!(label => "value")
        end.to raise_exception(described_class::ReservedLabelError)
      end
    end
  end

  describe "#validate_labelset!" do
    let(:expected_labels) { %i[method code] }

    it "returns a given valid label set" do
      hash = { method: "get", code: "200" }

      expect(validator.validate_labelset!(hash)).to eql(hash)
    end

    it "returns an exception if there are malformed labels" do
      expect do
        validator.validate_labelset!("method" => "get", :code => "200")
      end.to raise_exception(invalid, /keys given: \["method", :code\] vs. keys expected: \[:code, :method\]/)
    end

    it "raises an exception if there are unexpected labels" do
      expect do
        validator.validate_labelset!(method: "get", code: "200", exception: "NoMethodError")
      end.to raise_exception(invalid, /keys given: \[:code, :exception, :method\] vs. keys expected: \[:code, :method\]/)
    end

    it "raises an exception if there are missing labels" do
      expect do
        validator.validate_labelset!(method: "get")
      end.to raise_exception(invalid, /keys given: \[:method\] vs. keys expected: \[:code, :method\]/)

      expect do
        validator.validate_labelset!(code: "200")
      end.to raise_exception(invalid, /keys given: \[:code\] vs. keys expected: \[:code, :method\]/)
    end
  end
end
