# encoding: UTF-8

shared_examples_for Prometheus::Client::Metric do
  subject { described_class.new(:foo, 'foo description') }

  describe '.new' do
    it 'returns a new metric' do
      expect(subject).to be
    end

    it 'raises an exception if a reserved base label is used' do
      exception = Prometheus::Client::LabelSetValidator::ReservedLabelError

      expect do
        described_class.new(:foo, 'foo docstring', __name__: 'reserved')
      end.to raise_exception exception
    end

    it 'raises an exception if the given name is blank' do
      expect do
        described_class.new(nil, 'foo')
      end.to raise_exception ArgumentError
    end

    it 'raises an exception if docstring is missing' do
      expect do
        described_class.new(:foo, '')
      end.to raise_exception ArgumentError
    end

    it 'raises an exception if a metric name is invalid' do
      [
        'string',
        '42startsWithNumber'.to_sym,
        'abc def'.to_sym,
        'abcdef '.to_sym,
        "abc\ndef".to_sym,
      ].each do |name|
        expect do
          described_class.new(name, 'foo')
        end.to raise_exception(ArgumentError)
      end
    end
  end

  describe 'common_lables' do
    let(:class_labels) do
      { foo: :bar }
    end
    let(:instance_labels) do
      { bar: :baz }
    end
    before(:each) do
      described_class.common_labels = class_labels
    end

    it 'propagates common labels to instance base labels' do
      m = described_class.new(:name, 'desc', instance_labels)
      expect(m.base_labels).to eq(class_labels.merge(instance_labels))
    end

    it 'prefers instance labels over common labels' do
      instance_labels = class_labels
      key = class_labels.keys.first
      instance_labels[:key] = 'different value than in the class labels'

      m = described_class.new(:name, 'desc', instance_labels)
      expect(m.base_labels[key]).to eq(instance_labels[key])
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
      expect(subject.get(test: 'label')).to be_a(type)
    end
  end
end
