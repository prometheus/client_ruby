# encoding: UTF-8

require 'prometheus/client/label_set_validator'

describe Prometheus::Client::LabelSetValidator do
  let(:validator) { Prometheus::Client::LabelSetValidator.new }
  let(:invalid) { Prometheus::Client::LabelSetValidator::InvalidLabelSetError }

  describe '.new' do
    it 'returns an instance of a LabelSetValidator' do
      expect(validator).to be_a(Prometheus::Client::LabelSetValidator)
    end
  end

  describe '#valid?' do
    it 'returns true for a valid label check' do
      expect(validator.valid?(version: 'alpha')).to eql(true)
    end

    it 'raises Invaliddescribed_classError if a label set is not a hash' do
      expect do
        validator.valid?('invalid')
      end.to raise_exception invalid
    end

    it 'raises InvalidLabelError if a label key is not a symbol' do
      expect do
        validator.valid?('key' => 'value')
      end.to raise_exception(described_class::InvalidLabelError)
    end

    it 'raises InvalidLabelError if a label key starts with __' do
      expect do
        validator.valid?(__reserved__: 'key')
      end.to raise_exception(described_class::ReservedLabelError)
    end

    it 'raises ReservedLabelError if a label key is reserved' do
      [:job, :instance].each do |label|
        expect do
          validator.valid?(label => 'value')
        end.to raise_exception(described_class::ReservedLabelError)
      end
    end
  end

  describe '#validate' do
    it 'returns a given valid label set' do
      hash = { version: 'alpha' }

      expect(validator.validate(hash)).to eql(hash)
    end

    it 'raises an exception if a given label set is not valid' do
      input = 'broken'
      expect(validator).to receive(:valid?).with(input).and_raise(invalid)

      expect { validator.validate(input) }.to raise_exception(invalid)
    end

    it 'raises InvalidLabelSetError for varying label sets' do
      validator.validate(method: 'get', code: '200')

      expect do
        validator.validate(method: 'get', exception: 'NoMethodError')
      end.to raise_exception(invalid)
    end
  end
end
