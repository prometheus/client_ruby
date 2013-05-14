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
        subject.get.should eql(default)
      end

      it 'returns the current metric value for a given label set' do
        subject.get(:test => 'label').should eql(default)
      end
    end

    describe '#set' do
      it 'sets a metric value' do
        expect do
          subject.set({}, 42)
        end.to change { subject.get }.from(subject.default).to(42)
      end

      it 'sets a metric value for a given label set' do
        expect do
          expect do
            subject.set({ :test => 'value' }, 42)
          end.to change { subject.get(:test => 'value') }.from(subject.default).to(42)
        end.to_not change { subject.get }
      end
    end
  end
end
