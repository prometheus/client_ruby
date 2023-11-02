# encoding: UTF-8

require 'prometheus/client'
require 'prometheus/client/vm_histogram'
require 'examples/metric_example'

describe Prometheus::Client::VmHistogram do
  # Reset the data store
  before do
    Prometheus::Client.config.data_store = Prometheus::Client::DataStores::Synchronized.new
  end

  let(:expected_labels) { [] }

  let(:histogram) do
    described_class.new(:bar,
                        docstring: 'bar description',
                        labels: expected_labels)
  end

  it_behaves_like Prometheus::Client::Metric

  describe '#initialization' do
    it 'accepts buckets, but does not use it' do
      expect do
        described_class.new(:bar, docstring: 'bar description', buckets: [5, 2.5, 10])
      end.not_to raise_error
    end

    it 'raise error for `vmrange` label' do
      expect do
        described_class.new(:bar, docstring: 'bar description', labels: [:vmrange])
      end.to raise_error Prometheus::Client::LabelSetValidator::ReservedLabelError
    end
  end

  describe '#observe' do
    it 'records the given value' do
      expect do
        histogram.observe(5)
      end.to change { histogram.get }
    end

    it 'raise error for vmrange labels' do
      expect do
        histogram.observe(5, labels: { vmrange: 1 })
      end.to raise_error Prometheus::Client::LabelSetValidator::InvalidLabelSetError
    end

    context 'when value is zero' do
      it 'uses the special bucket' do
        histogram.observe(0)

        expect(histogram.get).to eq('0...1.000e-09' => 1.0, 'count' => 1.0, 'sum' => 0.0)
      end
    end

    context 'when value is one of 10^n' do
      it 'uses correct bucket' do
        histogram.observe(100)

        expect(histogram.get).to eq('8.799e+01...1.000e+02' => 1.0, 'count' => 1.0, 'sum' => 100.0)
      end
    end

    context 'when value is too big' do
      it 'uses the last bucket' do
        histogram.observe(1000000000000000000000000)

        expect(histogram.get).to eq('8.799e+17...1.000e+18' => 1.0, 'count' => 1.0, 'sum' => 1.0e+24)
      end
    end

    context 'with an expected label set' do
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
        .to eql(
          '2.783e+00...3.162e+00' => 1.0,
          '4.642e+00...5.275e+00' => 1.0,
          '1.292e+01...1.468e+01' => 1.0,
          '3.594e+00...4.084e+00' => 1.0,
          'sum' => 25.2,
          'count' => 4.0
        )
    end

    it 'returns a value which includes sum' do
      value = histogram.get(labels: { foo: 'bar' })

      expect(value["sum"]).to eql(25.2)
    end

    it 'returns a value which includes count' do
      value = histogram.get(labels: { foo: 'bar' })

      expect(value["count"]).to eql(4.0)
    end

    it 'uses zero as default value' do
      expect(histogram.get(labels: { foo: '' })).to eql(
        'sum' => 0.0,
        'count' => 0.0
      )
    end
  end

  describe '#values' do
    let(:expected_labels) { [:status] }

    it 'returns a hash of all recorded summaries' do
      histogram.observe(3, labels: { status: 'bar' })
      histogram.observe(6, labels: { status: 'foo' })
      histogram.observe(12, labels: { status: 'baz' })

      expect(histogram.values).to eql(
        { status: 'bar' } => { "2.783e+00...3.162e+00" => 1.0, "count" => 1.0, "sum" => 3.0 },
        { status: 'foo' } => { "5.995e+00...6.813e+00" => 1.0, "count" => 1.0, "sum" => 6.0 },
        { status: 'baz' } => { "1.136e+01...1.292e+01" => 1.0, "count" => 1.0, "sum" => 12.0 }
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
          { status: 'bar' } => { "sum" => 0.0, "count" => 0.0 },
          { status: 'foo' } => { "sum" => 0.0, "count" => 0.0 },
        )
      end
    end

    context "without labels" do
      it 'automatically initializes the metric' do
        expect(histogram.values).to eql(
          {} => { "sum" => 0.0, "count" => 0.0 }
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
        { foo: 'value1' } => { "6.813e+00...7.743e+00" => 1.0, "count" => 1.0, "sum" => 7.0 },
        { foo: 'value2' } => { "1.896e+01...2.154e+01" => 1.0, "count" => 1.0, "sum" => 20.0 }
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
          {foo: 'value1', bar: 'zzz'} => {"8.799e-01...1.000e+00"=>1.0, "count"=>1.0, "sum"=>1.0},
          {foo: 'value1', bar: 'aaa'} => {"8.799e-01...1.000e+00"=>1.0, "count"=>1.0, "sum"=>1.0},
          {foo: 'longervalue', bar: 'zzz'} => {"8.799e-01...1.000e+00"=>1.0, "count"=>1.0, "sum"=>1.0},
          {foo: 'longervalue', bar: 'aaa'} => {"8.799e-01...1.000e+00"=>1.0, "count"=>1.0, "sum"=>1.0}
        }

        expect(histogram.values).to eql(expected_values)
        expect(histogram_with_labels.values).to eql(expected_values)
      end
    end
  end
end
