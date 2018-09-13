# encoding: UTF-8

require 'prometheus/client/summary'
require 'examples/metric_example'

describe Prometheus::Client::Summary do
  let(:expected_labels) { [] }

  let(:summary) do
    Prometheus::Client::Summary.new(:bar,
                                    docstring: 'bar description',
                                    labels: expected_labels)
  end

  it_behaves_like Prometheus::Client::Metric do
    let(:type) { Prometheus::Client::Summary::Value }
  end

  describe '#initialization' do
    it 'raise error for `quantile` label' do
      expect do
        described_class.new(:bar, docstring: 'bar description', labels: [:quantile])
      end.to raise_error Prometheus::Client::LabelSetValidator::ReservedLabelError
    end
  end

  describe '#observe' do
    it 'records the given value' do
      expect do
        expect do
          summary.observe(5)
        end.to change { summary.get.sum }.from(0.0).to(5.0)
      end.to change { summary.get.total }.from(0.0).to(1.0)
    end

    it 'raise error for quantile labels' do
      expect do
        summary.observe(5, labels: { quantile: 1 })
      end.to raise_error Prometheus::Client::LabelSetValidator::ReservedLabelError
    end

    it 'raises an InvalidLabelSetError if sending unexpected labels' do
      expect do
        summary.observe(5, labels: { foo: 'bar' })
      end.to raise_error Prometheus::Client::LabelSetValidator::InvalidLabelSetError
    end

    context "with a an expected label set" do
      let(:expected_labels) { [:test] }

      it 'observes a value for a given label set' do
        expect do
          expect do
            summary.observe(5, labels: { test: 'value' })
          end.to change { summary.get(labels: { test: 'value' }).total }
        end.to_not change { summary.get(labels: { test: 'other' }).total }
      end
    end
  end

  describe '#get' do
    let(:expected_labels) { [:foo] }

    before do
      summary.observe(3, labels: { foo: 'bar' })
      summary.observe(5.2, labels: { foo: 'bar' })
      summary.observe(13, labels: { foo: 'bar' })
      summary.observe(4, labels: { foo: 'bar' })
    end

    it 'returns a value which responds to #sum and #total' do
      value = summary.get(labels: { foo: 'bar' })

      expect(value.sum).to eql(25.2)
      expect(value.total).to eql(4.0)
    end
  end

  describe '#values' do
    let(:expected_labels) { [:status] }

    it 'returns a hash of all recorded summaries' do
      summary.observe(3, labels: { status: 'bar' })
      summary.observe(5, labels: { status: 'foo' })

      expect(summary.values[{ status: 'bar' }].sum).to eql(3.0)
      expect(summary.values[{ status: 'foo' }].sum).to eql(5.0)
    end
  end
end
