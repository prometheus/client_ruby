# encoding: UTF-8

require 'prometheus/client'
require 'prometheus/client/summary'
require 'examples/metric_example'

describe Prometheus::Client::Summary do
  # Reset the data store
  before do
    Prometheus::Client.config.data_store = Prometheus::Client::DataStores::Synchronized.new
  end

  let(:expected_labels) { [] }

  let(:summary) do
    Prometheus::Client::Summary.new(:bar,
                                    docstring: 'bar description',
                                    labels: expected_labels)
  end

  it_behaves_like Prometheus::Client::Metric

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
        summary.observe(5)
      end.to change { summary.get }.
        from({ "count" => 0.0, "sum" => 0.0 }).
        to({ "count" => 1.0, "sum" => 5.0 })
    end

    it 'raise error for quantile labels' do
      expect do
        summary.observe(5, labels: { quantile: 1 })
      end.to raise_error Prometheus::Client::LabelSetValidator::InvalidLabelSetError
    end

    context "with a an expected label set" do
      let(:expected_labels) { [:test] }

      it 'observes a value for a given label set' do
        expect do
          expect do
            summary.observe(5, labels: { test: 'value' })
          end.to change { summary.get(labels: { test: 'value' })["count"] }
        end.to_not change { summary.get(labels: { test: 'other' })["count"] }
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
      expect(summary.get(labels: { foo: 'bar' })).
        to eql({ "count" => 4.0, "sum" => 25.2 })
    end
  end

  describe '#values' do
    let(:expected_labels) { [:status] }

    it 'returns a hash of all recorded summaries' do
      summary.observe(3, labels: { status: 'bar' })
      summary.observe(5, labels: { status: 'foo' })

      expect(summary.values).to eql(
        { status: 'bar' } => { "count" => 1.0, "sum" => 3.0 },
        { status: 'foo' } => { "count" => 1.0, "sum" => 5.0 },
      )
    end
  end

  describe 'with quantile objectives' do
    let(:objectives) { { 0.5 => 0.05, 0.9 => 0.01, 0.99 => 0.001 } }

    let(:summary_with_objectives) do
      Prometheus::Client::Summary.new(:bar_quantile,
                                      docstring: 'bar description',
                                      labels: expected_labels,
                                      objectives: objectives)
    end

    describe '#observe' do
      it 'records the given value with quantiles' do
        1000.times { |i| summary_with_objectives.observe(i) }
        result = summary_with_objectives.get
        expect(result["count"]).to eq(1000.0)
        expect(result["sum"]).to eq(499500.0)
        expect(result["0.5"]).to be_within(1000 * 0.05 * 2).of(500)
        expect(result["0.9"]).to be_within(1000 * 0.01 * 2).of(900)
        expect(result["0.99"]).to be_within(1000 * 0.001 * 2).of(990)
      end
    end

    describe '#get' do
      it 'returns NaN for quantiles with no observations' do
        result = summary_with_objectives.get
        expect(result["count"]).to eq(0.0)
        expect(result["sum"]).to eq(0.0)
        expect(result["0.5"]).to be_nan
        expect(result["0.9"]).to be_nan
        expect(result["0.99"]).to be_nan
      end
    end

    describe '#values' do
      it 'includes quantile values' do
        100.times { |i| summary_with_objectives.observe(i) }
        vals = summary_with_objectives.values
        label_set_values = vals[{}]
        expect(label_set_values).to have_key("0.5")
        expect(label_set_values).to have_key("0.9")
        expect(label_set_values).to have_key("0.99")
        expect(label_set_values).to have_key("count")
        expect(label_set_values).to have_key("sum")
      end
    end

    describe '#with_labels' do
      let(:expected_labels) { [:foo] }

      it 'passes through quantile settings' do
        with_labels = summary_with_objectives.with_labels(foo: 'bar')
        100.times { |i| with_labels.observe(i) }
        result = with_labels.get(labels: { foo: 'bar' })
        expect(result).to have_key("0.5")
        expect(result["count"]).to eq(100.0)
      end
    end
  end

  describe '#init_label_set' do
    context "with labels" do
      let(:expected_labels) { [:status] }

      it 'initializes the metric for a given label set' do
        expect(summary.values).to eql({})

        summary.init_label_set(status: 'bar')
        summary.init_label_set(status: 'foo')

        expect(summary.values).to eql(
          { status: 'bar' } => { "count" => 0.0, "sum" => 0.0 },
          { status: 'foo' } => { "count" => 0.0, "sum" => 0.0 },
        )
      end
    end

    context "without labels" do
      it 'automatically initializes the metric' do
        expect(summary.values).to eql(
          {} => { "count" => 0.0, "sum" => 0.0 },
        )
      end
    end
  end
end
