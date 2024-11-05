# encoding: UTF-8

require 'prometheus/client'
require 'prometheus/client/histogram_fixed'
require 'prometheus/client/data_stores/direct_file_store'
require 'examples/metric_example'

describe Prometheus::Client::HistogramFixed do
  # Reset the data store
  before do
    Prometheus::Client.config.data_store = Prometheus::Client::DataStores::Synchronized.new
  end

  let(:expected_labels) { [] }

  let(:histogram) do
    described_class.new(:bar,
                        docstring: 'bar description',
                        labels: expected_labels,
                        buckets: [2.5, 5, 10])
  end

  it_behaves_like Prometheus::Client::Metric

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

  describe ".linear_buckets" do
    it "generates buckets" do
      expect(described_class.linear_buckets(start: 1, width: 2, count: 5)).
        to eql([1.0, 3.0, 5.0, 7.0, 9.0])
    end
  end

  describe ".exponential_buckets" do
    it "generates buckets" do
      expect(described_class.exponential_buckets(start: 1, factor: 2, count: 5)).
        to eql([1.0, 2.0, 4.0, 8.0, 16.0])
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

      it 'raise error for empty labels' do
        expect do
          histogram.observe(5)
        end.to raise_error Prometheus::Client::LabelSetValidator::InvalidLabelSetError
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
        .to eql(
          "2.5" => 0.0, "5" => 2.0, "10" => 3.0, "+Inf" => 4.0, "sum" => 25.2
        )
    end

    it 'returns a value which includes sum' do
      value = histogram.get(labels: { foo: 'bar' })

      expect(value["sum"]).to eql(25.2)
    end

    it 'uses zero as default value' do
      expect(histogram.get(labels: { foo: '' })).to eql(
        "2.5" => 0.0, "5" => 0.0, "10" => 0.0, "+Inf" => 0.0, "sum" => 0.0
      )
    end
  end

  describe '#values' do
    let(:expected_labels) { [:status] }

    it 'returns a hash of all recorded summaries' do
      histogram.observe(3, labels: { status: 'bar' })
      histogram.observe(6, labels: { status: 'foo' })
      histogram.observe(10, labels: { status: 'baz' })

      expect(histogram.values).to eql(
        { status: 'bar' } => { "2.5" => 0.0, "5" => 1.0, "10" => 1.0, "+Inf" => 1.0, "sum" => 3.0 },
        { status: 'foo' } => { "2.5" => 0.0, "5" => 0.0, "10" => 1.0, "+Inf" => 1.0, "sum" => 6.0 },
        { status: 'baz' } => { "2.5" => 0.0, "5" => 0.0, "10" => 1.0, "+Inf" => 1.0, "sum" => 10.0 },
      )
    end
  end

  describe '#init_label_set' do
    context "with labels" do
      let(:expected_labels) { [:status] }

      it 'initializes the metric for a given label set' do
        expect(histogram.values).to eql({})

        histogram.init_label_set(status: 'bar')
        histogram.init_label_set(status: 'foo')

        expect(histogram.values).to eql(
          { status: 'bar' } => { "2.5" => 0.0, "5" => 0.0, "10" => 0.0, "+Inf" => 0.0, "sum" => 0.0 },
          { status: 'foo' } => { "2.5" => 0.0, "5" => 0.0, "10" => 0.0, "+Inf" => 0.0, "sum" => 0.0 },
        )
      end
    end

    context "without labels" do
      it 'automatically initializes the metric' do
        expect(histogram.values).to eql(
          {} => { "2.5" => 0.0, "5" => 0.0, "10" => 0.0, "+Inf" => 0.0, "sum" => 0.0 },
        )
      end
    end
  end

  describe '#with_labels' do
    let(:expected_labels) { [:foo] }

    it 'pre-sets labels for observations' do
      expect { histogram.observe(2) }
        .to raise_error(Prometheus::Client::LabelSetValidator::InvalidLabelSetError)
      expect { histogram.with_labels(foo: 'value').observe(2) }.not_to raise_error
    end

    it 'registers `with_labels` observations in the original metric store' do
      histogram.observe(7, labels: { foo: 'value1'})
      histogram_with_labels = histogram.with_labels({ foo: 'value2'})
      histogram_with_labels.observe(20)

      expected_values = {
        {foo: 'value1'} => {'2.5' => 0.0, '5' => 0.0, '10' => 1.0, '+Inf' => 1.0, 'sum' => 7.0},
        {foo: 'value2'} => {'2.5' => 0.0, '5' => 0.0, '10' => 0.0, '+Inf' => 1.0, 'sum' => 20.0}
      }
      expect(histogram_with_labels.values).to eql(expected_values)
      expect(histogram.values).to eql(expected_values)
    end

    context 'when using DirectFileStore' do
      before do
        Dir.glob('/tmp/prometheus_test/*').each { |file| File.delete(file) }
        Prometheus::Client.config.data_store = Prometheus::Client::DataStores::DirectFileStore.new(dir: '/tmp/prometheus_test')
      end

      after do
        Dir.glob('/tmp/prometheus_test/*').each { |file| File.delete(file) }
        Prometheus::Client.config.data_store = Prometheus::Client::DataStores::Synchronized.new
      end

      let(:expected_labels) { [:foo, :bar] }

      # This is a slightly weird test, and largely a duplicate of one in
      # spec/prometheus/client/metric_spec.rb.
      #
      # The reason we have this copy of the test is because histogram.rb
      # implements its own fix for the issue this test guards against due to
      # having slightly different constructor signature (which gets called in
      # `with_labels`).
      #
      # See the comment in spec/prometheus/client/metric_spec.rb for an
      # explanation of what this test is doing and why.
      it "doesn't corrupt the data files" do
        histogram_with_labels = histogram.with_labels({ foo: 'longervalue'})

        # Initialize / read the files for both views of the metric
        histogram.observe(1, labels: { foo: 'value1', bar: 'zzz'})
        histogram_with_labels.observe(1, labels: {bar: 'zzz'})

        # After both MetricStores have their files, add a new entry to both
        histogram.observe(1, labels: { foo: 'value1', bar: 'aaa'}) # If there's a bug, we partially overwrite { foo: 'longervalue', bar: 'zzz'}
        histogram_with_labels.observe(1, labels: {bar: 'aaa'}) # Extend the file so we read past that overwrite

        expect { histogram.values }.not_to raise_error # Check it hasn't corrupted our files
        expect { histogram_with_labels.values }.not_to raise_error # Check it hasn't corrupted our files

        expected_values = {
          {foo: 'value1', bar: 'zzz'} => {"2.5" => 1.0, "5"=>1.0, "10" => 1.0, "+Inf" => 1.0, "sum"=>1.0},
          {foo: 'value1', bar: 'aaa'} => {"2.5" => 1.0, "5"=>1.0, "10" => 1.0, "+Inf" => 1.0, "sum"=>1.0},
          {foo: 'longervalue', bar: 'zzz'} => {"2.5" => 1.0, "5"=>1.0, "10" => 1.0, "+Inf" => 1.0, "sum"=>1.0},
          {foo: 'longervalue', bar: 'aaa'} => {"2.5" => 1.0, "5"=>1.0, "10" => 1.0, "+Inf" => 1.0, "sum"=>1.0},
        }

        expect(histogram.values).to eql(expected_values)
        expect(histogram_with_labels.values).to eql(expected_values)
      end
    end
  end
end
