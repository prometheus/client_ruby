# encoding: UTF-8

shared_examples_for Prometheus::Client::Metric do
  subject { described_class.new(:foo, docstring: 'foo description') }

  describe '.new' do
    it 'returns a new metric' do
      expect(subject).to be
    end

    it 'raises an exception if a reserved base label is used' do
      exception = Prometheus::Client::LabelSetValidator::ReservedLabelError

      expect do
        described_class.new(:foo,
                            docstring: 'foo docstring',
                            preset_labels: { __name__: 'reserved' })
      end.to raise_exception exception
    end

    it 'raises an exception if the given name is blank' do
      expect do
        described_class.new(nil, docstring: 'foo')
      end.to raise_exception ArgumentError
    end

    it 'raises an exception if docstring is missing' do
      expect do
        described_class.new(:foo, docstring: '')
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
          described_class.new(name, docstring: 'foo')
        end.to raise_exception(ArgumentError)
      end
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

    context "with a subject that expects labels" do
      subject { described_class.new(:foo, docstring: 'Labels', labels: [:test]) }

      it 'returns the current metric value for a given label set' do
        expect(subject.get(labels: { test: 'label' })).to be_a(type)
      end
    end
  end
end
