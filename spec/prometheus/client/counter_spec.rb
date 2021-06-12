# encoding: UTF-8

require 'prometheus/client'
require 'prometheus/client/counter'
require 'examples/metric_example'
require 'prometheus/client/data_stores/direct_file_store'

describe Prometheus::Client::Counter do
  # Reset the data store
  before do
    Prometheus::Client.config.data_store = Prometheus::Client::DataStores::Synchronized.new
  end

  let(:expected_labels) { [] }

  let(:counter) do
    Prometheus::Client::Counter.new(:foo,
                                    docstring: 'foo description',
                                    labels: expected_labels)
  end

  it_behaves_like Prometheus::Client::Metric do
    let(:type) { Float }
  end

  describe '#increment' do
    it 'increments the counter' do
      expect do
        counter.increment
      end.to change { counter.get }.by(1.0)
    end

    it 'raises an InvalidLabelSetError if sending unexpected labels' do
      expect do
        counter.increment(labels: { test: 'label' })
      end.to raise_error Prometheus::Client::LabelSetValidator::InvalidLabelSetError
    end

    context "with a an expected label set" do
      let(:expected_labels) { [:test] }

      it 'increments the counter for a given label set' do
        expect do
          expect do
            counter.increment(labels: { test: 'label' })
          end.to change { counter.get(labels: { test: 'label' }) }.by(1.0)
        end.to_not change { counter.get(labels: { test: 'other' }) }
      end
    end

    it 'increments the counter by a given value' do
      expect do
        counter.increment(by: 5)
      end.to change { counter.get }.by(5.0)
    end

    it 'raises an ArgumentError on negative increments' do
      expect do
        counter.increment(by: -1)
      end.to raise_error ArgumentError
    end

    it 'returns the new counter value' do
      expect(counter.increment).to eql(1.0)
    end

    it 'is thread safe' do
      expect do
        Array.new(10) do
          Thread.new do
            10.times { counter.increment }
          end
        end.each(&:join)
      end.to change { counter.get }.by(100.0)
    end

    context "with non-string label values" do
      subject { described_class.new(:foo, docstring: 'Labels', labels: [:foo]) }

      it "converts labels to strings for consistent storage" do
        subject.increment(labels: { foo: :label })
        expect(subject.get(labels: { foo: 'label' })).to eq(1.0)
      end

      context "and some labels preset" do
        subject do
          described_class.new(:foo,
                              docstring: 'Labels',
                              labels: [:foo, :bar],
                              preset_labels: { foo: :label })
        end

        it "converts labels to strings for consistent storage" do
          subject.increment(labels: { bar: :label })
          expect(subject.get(labels: { foo: 'label', bar: 'label' })).to eq(1.0)
        end
      end
    end
  end

  describe '#init_label_set' do
    context "with labels" do
      let(:expected_labels) { [:test] }

      it 'initializes the metric for a given label set' do
        expect(counter.values).to eql({})

        counter.init_label_set(test: 'value')

        expect(counter.values).to eql({test: 'value'} => 0.0)
      end
    end

    context "without labels" do
      it 'automatically initializes the metric' do
        expect(counter.values).to eql({} => 0.0)
      end
    end
  end

  describe '#with_labels' do
    let(:expected_labels) { [:foo] }

    it 'pre-sets labels for observations' do
      expect { counter.increment }
        .to raise_error(Prometheus::Client::LabelSetValidator::InvalidLabelSetError)
      expect { counter.with_labels(foo: 'label').increment }.not_to raise_error
    end

    it 'registers `with_labels` observations in the original metric store' do
      counter.increment(labels: { foo: 'value1'})
      counter_with_labels = counter.with_labels({ foo: 'value2'})
      counter_with_labels.increment(by: 2)

      expect(counter_with_labels.values).to eql({foo: 'value1'} => 1.0, {foo: 'value2'} => 2.0)
      expect(counter.values).to eql({foo: 'value1'} => 1.0, {foo: 'value2'} => 2.0)
    end

    context 'when using DirectFileStore' do
      before do
        Dir.glob('/tmp/prometheus_test/*').each { |file| File.delete(file) }
        Prometheus::Client.config.data_store = Prometheus::Client::DataStores::DirectFileStore.new(dir: '/tmp/prometheus_test')
      end

      let(:expected_labels) { [:foo, :bar] }
      
      it "doesn't corrupt the data files" do
        counter_with_labels = counter.with_labels({ foo: 'longervalue'})

        # Initialize / read the files for both views of the metric
        counter.increment(labels: { foo: 'value1', bar: 'zzz'})
        counter_with_labels.increment(by: 2, labels: {bar: 'zzz'})

        # After both MetricStores have their files, add a new entry to both
        counter.increment(labels: { foo: 'value1', bar: 'aaa'})
        counter_with_labels.increment(by: 2, labels: {bar: 'aaa'})

        expect { counter.values }.not_to raise_error # Check it hasn't corrupted our files
        expect { counter_with_labels.values }.not_to raise_error # Check it hasn't corrupted our files

        expected_values = {
          {foo: 'value1', bar: 'zzz'} => 1.0,
          {foo: 'value1', bar: 'aaa'} => 1.0,
          {foo: 'longervalue', bar: 'zzz'} => 2.0,
          {foo: 'longervalue', bar: 'aaa'} => 2.0,
        }

        expect(counter.values).to eql(expected_values)
        expect(counter_with_labels.values).to eql(expected_values)
      end
    end
  end
end
