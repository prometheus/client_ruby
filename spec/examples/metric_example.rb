module Prometheus::Client
  shared_examples_for Metric do
    describe '.new' do
      it 'returns a new metric' do
        expect(described_class.new).to be
      end
    end

    describe '#type' do
      it 'returns the metric type as symbol' do
        expect(subject.type).to be_a(Symbol)
      end
    end

    describe '#get' do
      it 'returns the current metric value' do
        expect(subject.get).to be_a(type)
      end

      it 'returns the current metric value for a given label set' do
        expect(subject.get(:test => 'label')).to be_a(type)
      end
    end
  end
end
