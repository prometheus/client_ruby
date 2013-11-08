module Prometheus::Client
  shared_examples_for Metric do
    describe '.new' do
      it 'returns a new metric' do
        described_class.new.should be
      end
    end

    describe '#type' do
      it 'returns the metric type as symbol' do
        subject.type.should be_a(Symbol)
      end
    end

    describe '#get' do
      it 'returns the current metric value' do
        subject.get.should be_a(type)
      end

      it 'returns the current metric value for a given label set' do
        subject.get(:test => 'label').should be_a(type)
      end
    end
  end
end
