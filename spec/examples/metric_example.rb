# encoding: UTF-8

# TODO: Convert these tests to use a fake metric class rather than shared examples
#
# Right now, we're using shared examples that we include in every metric type's tests
# to validate the behaviour of the base metric class.
#
# This makes it difficult to test certain behaviour, as the interfaces of those metric
# types differ and these tests can end up needing to know about them.
#
# You can see that in the tests for #get, which depend on `type` which isn't defined in
# this file. The test files that include these shared examples have to do so with a block
# that provides the `type` variable.
#
# This cropped up in a much worse way when trying to test the code that makes sure label
# values are all strings. Writing a test here that gets included in all the real metric
# implementations is near impossible. You need your test to call a different method to
# alter a metric value (e.g. `set`, `increment` or `observe` depending on the metric type)
# which means having each concrete metric type's tests passing us a lambda that we can
# call agnostically of the metric type.
#
# The resultant code is confusing to follow, so we opted to duplicate those tests in each
# metric type's test file.
#
# Changing this file to implement a fake metric class (e.g. `FakeTestCounter`) would let
# us easily test the functionality of the base `Prometheus::Client::Metric` without
# getting caught up in the specifics of the real metric types.

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
