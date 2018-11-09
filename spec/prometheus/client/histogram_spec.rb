# encoding: UTF-8

require 'prometheus/client/histogram'
require 'examples/metric_example'

describe Prometheus::Client::Histogram do
  let(:expected_labels) { [] }

  let(:histogram) do
    described_class.new(:bar,
                        docstring: 'bar description',
                        labels: expected_labels,
                        buckets: [2.5, 5, 10])
  end

  it_behaves_like Prometheus::Client::Metric do
    let(:type) { Hash }
  end

  describe '#initialization' do
    it 'raise error for unsorted buckets' do
      expect do
        described_class.new(:bar, docstring: 'bar description', buckets: [5, 2.5, 10])
      end.to raise_error ArgumentError
    end

    it 'raise error for `le` label' do
      expect do
        described_class.new(:bar, docstring: 'bar description', labels: [:le])
      end.to raise_error Prometheus::Client::LabelSetValidator::ReservedLabelError
    end
  end

  describe '#observe' do
    it 'records the given value' do
      expect do
        histogram.observe(5)
      end.to change { histogram.get }
    end

    it 'raise error for le labels' do
      expect do
        histogram.observe(5, labels: { le: 1 })
      end.to raise_error Prometheus::Client::LabelSetValidator::ReservedLabelError
    end

    it 'raises an InvalidLabelSetError if sending unexpected labels' do
      expect do
        histogram.observe(5, labels: { foo: 'bar' })
      end.to raise_error Prometheus::Client::LabelSetValidator::InvalidLabelSetError
    end

    context "with a an expected label set" do
      let(:expected_labels) { [:test] }

      it 'observes a value for a given label set' do
        expect do
          expect do
            histogram.observe(5, labels: { test: 'value' })
          end.to change { histogram.get(labels: { test: 'value' }) }
        end.to_not change { histogram.get(labels: { test: 'other' }) }
      end
    end
  end

  describe '#get' do
    let(:expected_labels) { [:foo] }

    before do
      histogram.observe(3, labels: { foo: 'bar' })
      histogram.observe(5.2, labels: { foo: 'bar' })
      histogram.observe(13, labels: { foo: 'bar' })
      histogram.observe(4, labels: { foo: 'bar' })
    end

    it 'returns a set of buckets values' do
      expect(histogram.get(labels: { foo: 'bar' }))
        .to eql(2.5 => 0.0, 5 => 2.0, 10 => 3.0)
    end

    it 'returns a value which responds to #sum and #total' do
      value = histogram.get(labels: { foo: 'bar' })

      expect(value.sum).to eql(25.2)
      expect(value.total).to eql(4.0)
    end

    it 'uses zero as default value' do
      expect(histogram.get(labels: { foo: '' })).to eql(2.5 => 0.0, 5 => 0.0, 10 => 0.0)
    end
  end

  describe '#values' do
    let(:expected_labels) { [:status] }

    it 'returns a hash of all recorded summaries' do
      histogram.observe(3, labels: { status: 'bar' })
      histogram.observe(6, labels: { status: 'foo' })

      expect(histogram.values).to eql(
        { status: 'bar' } => { 2.5 => 0.0, 5 => 1.0, 10 => 1.0 },
        { status: 'foo' } => { 2.5 => 0.0, 5 => 0.0, 10 => 1.0 },
      )
    end
  end
end
