# frozen_string_literal: true

require "prometheus/client"
require "prometheus/client/counter"
require "examples/metric_example"

describe Prometheus::Client::Counter do
  # Reset the data store
  before do
    Prometheus::Client.config.data_store = Prometheus::Client::DataStores::Synchronized.new
  end

  let(:expected_labels) { [] }

  let(:counter) do
    described_class.new(:foo,
                                    docstring: "foo description",
                                    labels: expected_labels)
  end

  it_behaves_like Prometheus::Client::Metric do
    let(:type) { Float }
  end

  describe "#increment" do
    it "increments the counter" do
      expect do
        counter.increment
      end.to change(counter, :get).by(1.0)
    end

    it "raises an InvalidLabelSetError if sending unexpected labels" do
      expect do
        counter.increment(labels: { test: "label" })
      end.to raise_error Prometheus::Client::LabelSetValidator::InvalidLabelSetError
    end

    context "with a an expected label set" do
      let(:expected_labels) { [:test] }

      it "increments the counter for a given label set" do
        expect do
          expect do
            counter.increment(labels: { test: "label" })
          end.to change { counter.get(labels: { test: "label" }) }.by(1.0)
        end.to_not change { counter.get(labels: { test: "other" }) }
      end

      it "can pre-set labels using `with_labels`" do
        expect { counter.increment }.
          to raise_error(Prometheus::Client::LabelSetValidator::InvalidLabelSetError)
        expect { counter.with_labels(test: "label").increment }.not_to raise_error
      end
    end

    it "increments the counter by a given value" do
      expect do
        counter.increment(by: 5)
      end.to change(counter, :get).by(5.0)
    end

    it "raises an ArgumentError on negative increments" do
      expect do
        counter.increment(by: -1)
      end.to raise_error ArgumentError
    end

    it "returns the new counter value" do
      expect(counter.increment).to be(1.0)
    end

    it "is thread safe" do
      expect do
        Array.new(10) do
          Thread.new do
            10.times { counter.increment }
          end
        end.each(&:join)
      end.to change(counter, :get).by(100.0)
    end
  end
end
