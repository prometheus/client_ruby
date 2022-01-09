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

      # Testing for file corruption: this is weird and complicated, so it needs explaining
      #
      # Files get corrupted when we have two different instances of `FileMappedDict`
      # reading and writing the same file. This corruption is expected; we should never have
      # two instances of `FileMappedDict` for the same file. If we do, it's a bug in our client.
      #
      # To clarify, the bug is that *we ended up with two instances for the same file*, not
      # that the instances are now corrupting the file.
      #
      # This is why we're testing this in `with_labels`. It's the only use case we've found
      # were we ended up with two instances (before we fixed that bug). `with_labels` is
      # incidental, if we find another way to get "duplicate" instances, we should add this
      # same exact test, except for the first line, where we need to instead reproduce
      # whatever bug gets us that second instance.
      #
      # The first thing we need to understand is why having two instances of `FileMappedDict`
      # corrupts the files:
      #
      # `FileMappedDict` keeps track, in an internal variable, of how many bytes in the file
      # have been used. When adding a new "entry" (observing a new labelset), it serializes
      # it and adds it at "the end" (according to its internal byte counter), and it also updates
      # the counter at the beginning of the file. However, it never re-reads that counter
      # from the file, because there shouldn't be any reason for it to have changed.
      #
      # If there are two instances pointing to the same file, initially they will both
      # share that internal counter, as they do the first read of the file, but if then
      # each of them adds an entry, their internal "length" counters will disagree, and
      # they'll start overwriting each other's entries.
      #
      # Importantly, if all of the entries happen to have the same length, it will be "fine".
      # Some of the labelsets will effectively disappear, but there will be no corruption,
      # because all the important things will fall in the right offsets by pure chance. This
      # would be very rare in production, but in a test, it's what normally happens because
      # we set all labels to "foo", "bar", etc. This is the reason for "longervalue" below,
      # we need to have different labelset lenghts to reproduce the corruption.
      #
      # With this background about the internals, we can now get to why the specific sequence of
      # steps below ends up in corrupted files.
      #
      # For this to make sense, i'll need to describe the contents of the file at each step.
      # I'll represent it like this: `27|labelset1,value1|labelset2,value2|labelset3,value3|`
      #
      # These are not the bytes we store in the file, but conceptually it's equivalent,
      # with two caveats:
      # - The counter at the beginning (27 == 3 * 9) here shows the combined length of labelsets.
      #   It'd normally also include the length of values, but doing that makes this explanation
      #   much harder to follow.
      # - Each entry also starts with a 4-byte int specifying the length of its labelset, so
      #   we know how much to read. Again, I'm omitting that for readability.
      #
      #
      # Steps to reproduce:
      # - We declare `counter` and `counter_with_labels` as a clone. Neither has read the file.
      # - We increment `counter`, which creates the file and adds the entry ("labelset1")
      #     - File: `9|labelset1,value1|`
      # - We increment `counter_with_labels`, which reads the file, and adds the new entry
      #   to it ("muchlongerlabelset2").
      #     - File: `28|labelset1,value1|muchlongerlabelset2, value2|`
      #     - `counter` and `counter_with_labels` now disagree about the length of this file
      #       (`counter` doesn't know the file has grown).
      # - We now add a new entry to `counter` ("labelset3"), which thinks the file is shorter
      #   than it actually is.
      #     - File: `18|labelset1,value1|labelset3,value3|et2, value2|`
      #     - The initial counter reflects both labelsets for `counter`; then we have those
      #       labelsetsp; and finally some "garbage" after the "end" (the garbage is the
      #       last few bytes of the much longer entry added before by `counter_with_labels`)
      #     - so far, though, we're still good. If you read the file, all entries are "fine",
      #       because you're only reading up to the "18" length specified at the beginning.
      #     - for the problem to manifest itself, we need to increment that counter at the
      #       beginning, so we'll read the garbage. **BUT**, if we add a new labelset to
      #       `counter`, it'll overwrite the "garbage" with good data, and the file will
      #       continue to be fine.
      # - We add a new entry to `counter_with_labels`. This updates the length counter at
      #   the beginning of the file.
      #     - File: `47|labelset1,value1|labelset3,value3|et2, value2|muchlongerlabelset4, value4|`
      #
      # - Now the file is properly corrupted. When reading it, `FileMappedDict` sees:
      #    - labelset1,value1 (cool)
      #    - labelset3,value3 (cool)
      #    - et2, value2 (boom)
      #      |-> the beginning of this entry is garbage because we're actually at the middle
      #          of an entry, not a beginning.
      #
      # What actually breaks is that each of these entries is expected to have, at their
      # beginning, the length in bytes of its labelset, so we know how much to read.
      # Now we have garbage in that position, and `FileMappedDict` will either:
      #   - Try to interpret those four bytes as a long, get an invalid result.
      #   - Try to read an invalid amount of data (maybe a negative amount).
      #   - After reading the labelset, try to read the float and go past the end of the file
      #   - Actually read what it thinks is a float, try to `unpack` it, and fail because
      #       it's actually garbage.
      #   - I'm sure there are other fun ways for it to fail.
      it "doesn't corrupt the data files" do
        counter_with_labels = counter.with_labels({ foo: 'longervalue'})

        # Initialize / read the files for both views of the metric
        counter.increment(labels: { foo: 'value1', bar: 'zzz'})
        counter_with_labels.increment(by: 2, labels: {bar: 'zzz'})

        # After both MetricStores have their files, add a new entry to both
        counter.increment(labels: { foo: 'value1', bar: 'aaa'}) # If there's a bug, we partially overwrite { foo: 'longervalue', bar: 'zzz'}
        counter_with_labels.increment(by: 2, labels: {bar: 'aaa'}) # Extend the file so we read past that overwrite

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
