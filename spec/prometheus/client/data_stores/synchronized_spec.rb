# encoding: UTF-8

require 'prometheus/client/data_stores/synchronized'
require 'examples/data_store_example'

describe Prometheus::Client::DataStores::Synchronized do
  subject { described_class.new }
  let(:metric_store) { subject.for_metric(:metric_name, metric_type: :counter) }

  it_behaves_like Prometheus::Client::DataStores

  it "does not accept Metric Settings" do
    expect do
      subject.for_metric(:metric_name,
                         metric_type: :counter,
                         metric_settings: { some_setting: true })
    end.to raise_error(Prometheus::Client::DataStores::Synchronized::InvalidStoreSettingsError)
  end

  it '#set an #get' do
    metric_store.set(labels: { name: 'test' }, val: 1)
    expect(metric_store.get(labels: { name: 'test' })).to eq(1.0)
  end

  it '#set and #values' do
    metric_store.set(labels: { name: 'test1' }, val: 1)
    metric_store.set(labels: { name: 'test2' }, val: 2)

    expect(metric_store.all_values).to eq({ { name: 'test1' } => 1.0, { name: 'test2' } => 2.0 })
  end
end
