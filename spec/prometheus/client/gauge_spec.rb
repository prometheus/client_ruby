# encoding: UTF-8

require 'prometheus/client'
require 'prometheus/client/gauge'
require 'examples/metric_example'

describe Prometheus::Client::Gauge do
  # Reset the data store
  before do
    Prometheus::Client.config.data_store = Prometheus::Client::DataStores::Synchronized.new
  end

  let(:expected_labels) { [] }

  let(:gauge) do
    Prometheus::Client::Gauge.new(:foo,
                                  docstring: 'foo description',
                                  labels: expected_labels)
  end

  it_behaves_like Prometheus::Client::Metric do
    let(:type) { Float }
  end

  describe '#set' do
    it 'sets a metric value' do
      expect do
        gauge.set(42)
      end.to change { gauge.get }.from(0).to(42)
    end

    it 'raises an InvalidLabelSetError if sending unexpected labels' do
      expect do
        gauge.set(42, labels: { test: 'value' })
      end.to raise_error Prometheus::Client::LabelSetValidator::InvalidLabelSetError
    end

    context "with a an expected label set" do
      let(:expected_labels) { [:test] }

      it 'sets a metric value for a given label set' do
        expect do
          expect do
            gauge.set(42, labels: { test: 'value' })
          end.to change { gauge.get(labels: { test: 'value' }) }.from(0).to(42)
        end.to_not change { gauge.get(labels: { test: 'other' }) }
      end
    end

    context 'given an invalid value' do
      it 'raises an ArgumentError' do
        expect do
          gauge.set(nil)
        end.to raise_exception(ArgumentError)
      end
    end
  end

  describe '#increment' do
    before do
      gauge.set(0, labels: RSpec.current_example.metadata[:labels] || {})
    end

    it 'increments the gauge' do
      expect do
        gauge.increment
      end.to change { gauge.get }.by(1.0)
    end

    it 'raises an InvalidLabelSetError if sending unexpected labels' do
      expect do
        gauge.increment(labels: { test: 'value' })
      end.to raise_error Prometheus::Client::LabelSetValidator::InvalidLabelSetError
    end

    context "with a an expected label set" do
      let(:expected_labels) { [:test] }

      it 'increments the gauge for a given label set', labels: { test: 'one' } do
        expect do
          expect do
            gauge.increment(labels: { test: 'one' })
          end.to change { gauge.get(labels: { test: 'one' }) }.by(1.0)
        end.to_not change { gauge.get(labels: { test: 'another' }) }
      end
    end

    it 'increments the gauge by a given value' do
      expect do
        gauge.increment(by: 5)
      end.to change { gauge.get }.by(5.0)
    end

    it 'returns the new gauge value' do
      expect(gauge.increment).to eql(1.0)
    end

    it 'is thread safe' do
      expect do
        Array.new(10) do
          Thread.new do
            10.times { gauge.increment }
          end
        end.each(&:join)
      end.to change { gauge.get }.by(100.0)
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

  describe '#decrement' do
    before do
      gauge.set(0, labels: RSpec.current_example.metadata[:labels] || {})
    end

    it 'decrements the gauge' do
      expect do
        gauge.decrement
      end.to change { gauge.get }.by(-1.0)
    end

    it 'raises an InvalidLabelSetError if sending unexpected labels' do
      expect do
        gauge.decrement(labels: { test: 'value' })
      end.to raise_error Prometheus::Client::LabelSetValidator::InvalidLabelSetError
    end

    context "with a an expected label set" do
      let(:expected_labels) { [:test] }

      it 'decrements the gauge for a given label set', labels: { test: 'one' } do
        expect do
          expect do
            gauge.decrement(labels: { test: 'one' })
          end.to change { gauge.get(labels: { test: 'one' }) }.by(-1.0)
        end.to_not change { gauge.get(labels: { test: 'another' }) }
      end
    end

    it 'decrements the gauge by a given value' do
      expect do
        gauge.decrement(by: 5)
      end.to change { gauge.get }.by(-5.0)
    end

    it 'returns the new gauge value' do
      expect(gauge.decrement).to eql(-1.0)
    end

    it 'is thread safe' do
      expect do
        Array.new(10) do
          Thread.new do
            10.times { gauge.decrement }
          end
        end.each(&:join)
      end.to change { gauge.get }.by(-100.0)
    end
  end

  describe '#init_label_set' do
    context "with labels" do
      let(:expected_labels) { [:test] }

      it 'initializes the metric for a given label set' do
        expect(gauge.values).to eql({})

        gauge.init_label_set(test: 'value')

        expect(gauge.values).to eql({test: 'value'} => 0.0)
      end
    end

    context "without labels" do
      it 'automatically initializes the metric' do
        expect(gauge.values).to eql({} => 0.0)
      end
    end
  end

  describe '#with_labels' do
    let(:expected_labels) { [:foo] }

    it 'pre-sets labels for observations' do
      expect { gauge.set(10) }
        .to raise_error(Prometheus::Client::LabelSetValidator::InvalidLabelSetError)
      expect { gauge.with_labels(foo: 'value').set(10) }.not_to raise_error
    end

    it 'registers `with_labels` observations in the original metric store' do
      gauge.set(1, labels: { foo: 'value1'})
      gauge_with_labels = gauge.with_labels({ foo: 'value2'})
      gauge_with_labels.set(2)

      expect(gauge_with_labels.values).to eql({foo: 'value1'} => 1.0, {foo: 'value2'} => 2.0)
      expect(gauge.values).to eql({foo: 'value1'} => 1.0, {foo: 'value2'} => 2.0)
    end
  end
end
