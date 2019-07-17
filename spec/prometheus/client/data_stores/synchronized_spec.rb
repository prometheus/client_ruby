# frozen_string_literal: true

require "prometheus/client/data_stores/synchronized"
require "examples/data_store_example"

describe Prometheus::Client::DataStores::Synchronized do
  subject(:store) { described_class.new }

  let(:metric_store) { subject.for_metric(:metric_name, metric_type: :counter) }

  it_behaves_like Prometheus::Client::DataStores

  context "supplying metric_setting" do
    subject(:for_metric) do
      store.for_metric(
        :metric_name, metric_type: :counter, metric_settings: { some_setting: true }
      )
    end

    it "raises" do
      expect { for_metric }.to raise_error(
        Prometheus::Client::DataStores::Synchronized::InvalidStoreSettingsError,
      )
    end
  end
end
