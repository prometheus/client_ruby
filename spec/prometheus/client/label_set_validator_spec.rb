# encoding: UTF-8

require 'prometheus/client/label_set_validator'

describe Prometheus::Client::LabelSetValidator do
  let(:expected_labels) { [] }
  let(:additional_reserved_labels) { [] }
  let(:validator) do
    Prometheus::Client::LabelSetValidator.new(expected_labels: expected_labels, reserved_labels: additional_reserved_labels)
  end
  let(:invalid) { Prometheus::Client::LabelSetValidator::InvalidLabelSetError }

  describe '.new' do
    it 'returns an instance of a LabelSetValidator' do
      expect(validator).to be_a(Prometheus::Client::LabelSetValidator)
    end
  end

  describe '#validate_symbols!' do
    it 'returns true for a valid label check' do
      expect(validator.validate_symbols!(version: 'alpha')).to eql(true)
    end

    it 'raises InvalidLabelSetError if a label set is not a hash' do
      expect do
        validator.validate_symbols!('invalid')
      end.to raise_exception invalid
    end

    it 'raises InvalidLabelError if a label key is not a symbol' do
      expect do
        validator.validate_symbols!('key' => 'value')
      end.to raise_exception(described_class::InvalidLabelError)
    end

    it 'raises InvalidLabelError if a label key starts with __' do
      expect do
        validator.validate_symbols!(__reserved__: 'key')
      end.to raise_exception(described_class::ReservedLabelError)
    end

    it 'raises InvalidLabelError if a label key contains invalid characters' do
      expect do
        validator.validate_symbols!(:@foo => 'key')
      end.to raise_exception(described_class::InvalidLabelError)
    end

    context "with only the base set of reserved labels" do
      it "doesn't raise ReservedLabelError for the additional reserved label" do
        expect { validator.validate_symbols!(additional: 'value') }.
          to_not raise_exception
      end

      it 'raises ReservedLabelError if a label key is reserved' do
        expect { validator.validate_symbols!(pid: 'value') }.
          to raise_exception(described_class::ReservedLabelError)
      end
    end

    context "with an additional reserved label" do
      let(:additional_reserved_labels) { [:additional] }

      it 'raises ReservedLabelError if a label key is reserved' do
        [:additional, :pid].each do |label|
          expect do
            validator.validate_symbols!(label => 'value')
          end.to raise_exception(described_class::ReservedLabelError)
        end
      end
    end
  end

  describe '#validate_labelset!' do
    let(:expected_labels) { [:method, :code] }

    it 'returns a given valid label set' do
      hash = { method: 'get', code: '200' }

      expect(validator.validate_labelset!(hash)).to eql(hash)
    end

    it 'returns an exception if there are malformed labels' do
      expect do
        validator.validate_labelset!('method' => 'get', :code => '200')
      end.to raise_exception(invalid, /keys given: \["method", :code\] vs. keys expected: \[:code, :method\]/)

    end

    it 'raises an exception if there are unexpected labels' do
      expect do
        validator.validate_labelset!(method: 'get', code: '200', exception: 'NoMethodError')
      end.to raise_exception(invalid, /keys given: \[:method, :code, :exception\] vs. keys expected: \[:code, :method\]/)
    end

    it 'raises an exception if there are missing labels' do
      expect do
        validator.validate_labelset!(method: 'get')
      end.to raise_exception(invalid, /keys given: \[:method\] vs. keys expected: \[:code, :method\]/)

      expect do
        validator.validate_labelset!(code: '200')
      end.to raise_exception(invalid, /keys given: \[:code\] vs. keys expected: \[:code, :method\]/)
    end
  end
end
