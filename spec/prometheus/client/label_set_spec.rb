require 'prometheus/client/label_set'

module Prometheus::Client
  describe LabelSet do
    describe '.new' do
      it 'returns a valid label set' do
        hash = { :version => 'alpha' }

        expect(LabelSet.new(hash)).to eql(hash)
      end

      it 'raises InvalidLabelSetError if a label set is not a hash' do
        expect do
          LabelSet.new('invalid')
        end.to raise_exception(LabelSet::InvalidLabelSetError)
      end

      it 'raises InvalidLabelError if a label key is not a symbol' do
        expect do
          LabelSet.new('key' => 'value')
        end.to raise_exception(LabelSet::InvalidLabelError)
      end

      it 'raises ReservedLabelError if a label key is reserved' do
        [:name, :job, :instance].each do |label|
          expect do
            LabelSet.new(label => 'value')
          end.to raise_exception(LabelSet::ReservedLabelError)
        end
      end
    end
  end
end
