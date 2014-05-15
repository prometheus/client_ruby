# encoding: UTF-8

require 'prometheus/client/label_set'

describe Prometheus::Client::LabelSet do
  describe '.new' do
    it 'returns a valid label set' do
      hash = { version: 'alpha' }

      expect(described_class.new(hash)).to eql(hash)
    end

    it 'raises Invaliddescribed_classError if a label set is not a hash' do
      expect do
        described_class.new('invalid')
      end.to raise_exception(described_class::InvalidLabelSetError)
    end

    it 'raises InvalidLabelError if a label key is not a symbol' do
      expect do
        described_class.new('key' => 'value')
      end.to raise_exception(described_class::InvalidLabelError)
    end

    it 'raises InvalidLabelError if a label key starts with __' do
      expect do
        described_class.new(__reserved__: 'key')
      end.to raise_exception(described_class::ReservedLabelError)
    end

    it 'raises ReservedLabelError if a label key is reserved' do
      [:job, :instance].each do |label|
        expect do
          described_class.new(label => 'value')
        end.to raise_exception(described_class::ReservedLabelError)
      end
    end
  end
end
