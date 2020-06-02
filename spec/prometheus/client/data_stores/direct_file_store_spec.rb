# encoding: UTF-8

require 'prometheus/client/data_stores/direct_file_store'
require 'examples/data_store_example'

describe Prometheus::Client::DataStores::DirectFileStore do
  subject { described_class.new(dir: "/tmp/prometheus_test") }
  let(:metric_store) { subject.for_metric(:metric_name, metric_type: :counter) }

  # Reset the PStores
  before do
    Dir.glob('/tmp/prometheus_test/*').each { |file| File.delete(file) }
    # This doesn't actually work, btw, but it's what would have to be done.
    Prometheus::Client::DataStores::DirectFileStore::MetricStore.shared_store_opened_by_pid = nil
  end

  it_behaves_like Prometheus::Client::DataStores

  it "only accepts valid :aggregation as Metric Settings" do
    expect do
      subject.for_metric(:metric_name,
                         metric_type: :counter,
                         metric_settings: { aggregation: Prometheus::Client::DataStores::DirectFileStore::SUM })
    end.not_to raise_error

    expect do
      subject.for_metric(:metric_name,
                         metric_type: :counter,
                         metric_settings: { aggregation: :invalid })
    end.to raise_error(Prometheus::Client::DataStores::DirectFileStore::InvalidStoreSettingsError)

    expect do
      subject.for_metric(:metric_name,
                         metric_type: :counter,
                         metric_settings: { some_setting: true })
    end.to raise_error(Prometheus::Client::DataStores::DirectFileStore::InvalidStoreSettingsError)
  end

  it "raises when aggregating if we get to that that point with an invalid aggregation mode" do
    # This is basically just for coverage of a safety clause that can never be reached
    allow(subject).to receive(:validate_metric_settings) # turn off validation

    metric = subject.for_metric(:metric_name,
                                metric_type: :counter,
                                metric_settings: { aggregation: :invalid })
    metric.increment(labels: {}, by: 1)

    expect do
      metric.all_values
    end.to raise_error(Prometheus::Client::DataStores::DirectFileStore::InvalidStoreSettingsError)
  end

  it "opens the same file twice, if it already exists" do
    # Testing this simply for coverage
    ms = metric_store
    ms.increment(labels: {}, by: 1)

    ms2 = subject.for_metric(:metric_name, metric_type: :counter)
    ms2.increment(labels: {}, by: 1)
  end

  context "when process is forked" do
    it "opens a new internal store to avoid two processes using the same file" do
      allow(Process).to receive(:pid).and_return(12345)
      metric_store = subject.for_metric(:metric_name, metric_type: :counter)
      metric_store.increment(labels: {}, by: 1)

      allow(Process).to receive(:pid).and_return(23456)
      metric_store.increment(labels: {}, by: 1)
      expect(Dir.glob('/tmp/prometheus_test/*').size).to eq(2)
      expect(metric_store.all_values).to eq({} => 2.0)
    end
  end

  it "coalesces values irrespective of the order of labels" do
    metric_store1 = subject.for_metric(:metric_name, metric_type: :counter)
    metric_store1.increment(labels: { foo: "1", bar: "1" }, by: 1)
    metric_store1.increment(labels: { foo: "1", bar: "2" }, by: 7)
    metric_store1.increment(labels: { foo: "2", bar: "1" }, by: 3)

    metric_store1.increment(labels: { foo: "1", bar: "1" }, by: 10)
    metric_store1.increment(labels: { bar: "1", foo: "1" }, by: 10)

    expect(metric_store1.all_values).to eq(
                                          { foo: "1", bar: "1" } => 21.0,
                                          { foo: "1", bar: "2" } => 7.0,
                                          { foo: "2", bar: "1" } => 3.0,
                                          )
  end

  context "for a non-gauge metric" do
    it "sums values from different processes by default" do
      allow(Process).to receive(:pid).and_return(12345)
      metric_store1 = subject.for_metric(:metric_name, metric_type: :counter)
      metric_store1.set(labels: { foo: "bar" }, val: 1)
      metric_store1.set(labels: { foo: "baz" }, val: 7)
      metric_store1.set(labels: { foo: "yyy" }, val: 3)

      allow(Process).to receive(:pid).and_return(23456)
      metric_store2 = subject.for_metric(:metric_name, metric_type: :counter)
      metric_store2.set(labels: { foo: "bar" }, val: 3)
      metric_store2.set(labels: { foo: "baz" }, val: 2)
      metric_store2.set(labels: { foo: "zzz" }, val: 1)

      expect(metric_store2.all_values).to eq(
        { foo: "bar" } => 4.0,
        { foo: "baz" } => 9.0,
        { foo: "yyy" } => 3.0,
        { foo: "zzz" } => 1.0,
      )

      # Both processes should return the same value
      expect(metric_store1.all_values).to eq(metric_store2.all_values)
    end
  end

  context "for a gauge metric" do
    it "exposes each process's individual value by default" do
      allow(Process).to receive(:pid).and_return(12345)
      metric_store1 = subject.for_metric(
        :metric_name,
        metric_type: :gauge,
      )
      metric_store1.set(labels: { foo: "bar" }, val: 1)
      metric_store1.set(labels: { foo: "baz" }, val: 7)
      metric_store1.set(labels: { foo: "yyy" }, val: 3)

      allow(Process).to receive(:pid).and_return(23456)
      metric_store2 = subject.for_metric(
        :metric_name,
        metric_type: :gauge,
      )
      metric_store2.set(labels: { foo: "bar" }, val: 3)
      metric_store2.set(labels: { foo: "baz" }, val: 2)
      metric_store2.set(labels: { foo: "zzz" }, val: 1)

      expect(metric_store1.all_values).to eq(
        { foo: "bar", pid: "12345" } => 1.0,
        { foo: "bar", pid: "23456" } => 3.0,
        { foo: "baz", pid: "12345" } => 7.0,
        { foo: "baz", pid: "23456" } => 2.0,
        { foo: "yyy", pid: "12345" } => 3.0,
        { foo: "zzz", pid: "23456" } => 1.0,
      )

      # Both processes should return the same value
      expect(metric_store1.all_values).to eq(metric_store2.all_values)
    end

    it "coalesces values irrespective of the order of labels" do
      allow(Process).to receive(:pid).and_return(12345)
      metric_store1 = subject.for_metric(:metric_name, metric_type: :gauge)
      metric_store1.set(labels: { foo: "1", bar: "1" }, val: 1)
      metric_store1.set(labels: { foo: "1", bar: "2" }, val: 7)
      metric_store1.set(labels: { foo: "2", bar: "1" }, val: 3)

      metric_store1.set(labels: { bar: "1", foo: "1" }, val: 10)

      expect(metric_store1.all_values).to eq(
                                            { foo: "1", bar: "1", pid: "12345" } => 10.0,
                                            { foo: "1", bar: "2", pid: "12345" } => 7.0,
                                            { foo: "2", bar: "1", pid: "12345" } => 3.0,
                                            )

    end
  end

  context "with a metric that takes MAX instead of SUM" do
    it "reports the maximum values from different processes" do
      allow(Process).to receive(:pid).and_return(12345)
      metric_store1 = subject.for_metric(
        :metric_name,
        metric_type: :gauge,
        metric_settings: { aggregation: :max }
      )
      metric_store1.set(labels: { foo: "bar" }, val: 1)
      metric_store1.set(labels: { foo: "baz" }, val: 7)
      metric_store1.set(labels: { foo: "yyy" }, val: 3)

      allow(Process).to receive(:pid).and_return(23456)
      metric_store2 = subject.for_metric(
        :metric_name,
        metric_type: :gauge,
        metric_settings: { aggregation: :max }
      )
      metric_store2.set(labels: { foo: "bar" }, val: 3)
      metric_store2.set(labels: { foo: "baz" }, val: 2)
      metric_store2.set(labels: { foo: "zzz" }, val: 1)

      expect(metric_store1.all_values).to eq(
        { foo: "bar" } => 3.0,
        { foo: "baz" } => 7.0,
        { foo: "yyy" } => 3.0,
        { foo: "zzz" } => 1.0,
      )

      # Both processes should return the same value
      expect(metric_store1.all_values).to eq(metric_store2.all_values)
    end
  end

  context "with a metric that takes MIN instead of SUM" do
    it "reports the minimum values from different processes" do
      allow(Process).to receive(:pid).and_return(12345)
      metric_store1 = subject.for_metric(
        :metric_name,
        metric_type: :gauge,
        metric_settings: { aggregation: :min }
      )
      metric_store1.set(labels: { foo: "bar" }, val: 1)
      metric_store1.set(labels: { foo: "baz" }, val: 7)
      metric_store1.set(labels: { foo: "yyy" }, val: 3)

      allow(Process).to receive(:pid).and_return(23456)
      metric_store2 = subject.for_metric(
        :metric_name,
        metric_type: :gauge,
        metric_settings: { aggregation: :min }
      )
      metric_store2.set(labels: { foo: "bar" }, val: 3)
      metric_store2.set(labels: { foo: "baz" }, val: 2)
      metric_store2.set(labels: { foo: "zzz" }, val: 1)

      expect(metric_store1.all_values).to eq(
        { foo: "bar" } => 1.0,
        { foo: "baz" } => 2.0,
        { foo: "yyy" } => 3.0,
        { foo: "zzz" } => 1.0,
      )

      # Both processes should return the same value
      expect(metric_store1.all_values).to eq(metric_store2.all_values)
    end
  end

  context "with a metric that takes ALL instead of SUM" do
    it "reports all the values from different processes" do
      allow(Process).to receive(:pid).and_return(12345)
      metric_store1 = subject.for_metric(
        :metric_name,
        metric_type: :counter,
        metric_settings: { aggregation: :all }
      )
      metric_store1.set(labels: { foo: "bar" }, val: 1)
      metric_store1.set(labels: { foo: "baz" }, val: 7)
      metric_store1.set(labels: { foo: "yyy" }, val: 3)

      allow(Process).to receive(:pid).and_return(23456)
      metric_store2 = subject.for_metric(
        :metric_name,
        metric_type: :counter,
        metric_settings: { aggregation: :all }
      )
      metric_store2.set(labels: { foo: "bar" }, val: 3)
      metric_store2.set(labels: { foo: "baz" }, val: 2)
      metric_store2.set(labels: { foo: "zzz" }, val: 1)

      expect(metric_store1.all_values).to eq(
        { foo: "bar", pid: "12345" } => 1.0,
        { foo: "bar", pid: "23456" } => 3.0,
        { foo: "baz", pid: "12345" } => 7.0,
        { foo: "baz", pid: "23456" } => 2.0,
        { foo: "yyy", pid: "12345" } => 3.0,
        { foo: "zzz", pid: "23456" } => 1.0,
      )

      # Both processes should return the same value
      expect(metric_store1.all_values).to eq(metric_store2.all_values)
    end
  end

  it "resizes the File if metrics get too big" do
     truncate_calls_count = 0
     allow_any_instance_of(Prometheus::Client::DataStores::DirectFileStore::FileMappedDict).
       to receive(:resize_file).and_wrap_original do |original_method, *args, &block|
    
       truncate_calls_count += 1
       original_method.call(*args, &block)
     end

    really_long_string = "a" * 500_000
    10.times do |i|
      metric_store.set(labels: { foo: "#{ really_long_string }#{ i }" }, val: 1)
    end

    expect(truncate_calls_count).to be >= 3
  end

  context "with all metrics in one single file" do
    subject { described_class.new(dir: "/tmp/prometheus_test", separate_files_per_metric: false) }

    let(:metric_store1) { subject.for_metric(:metric_name, metric_type: :counter) }
    let(:metric_store2) { subject.for_metric(:metric_name2, metric_type: :counter) }

    it "stores all metrics into one file" do
      metric_store1.increment(labels: {a: "x", b: "x"}, by: 1)
      metric_store1.increment(labels: {a: "x", b: "zzz"}, by: 2)
      metric_store2.increment(labels: {a: "x", b: "x"}, by: 3)

      expect(Dir.glob('/tmp/prometheus_test/*').length).to eq(1)
    end

    it "exports values correctly" do
      metric_store1.increment(labels: {a: "x", b: "x"}, by: 1)
      metric_store1.increment(labels: {a: "x", b: "zzz"}, by: 2)
      metric_store2.increment(labels: {a: "x", b: "x"}, by: 3)

      expect(metric_store1.all_values).to eq(
        {a: "x", b: "x"} => 1.0,
        {a: "x", b: "zzz"} => 2.0,
      )

      expect(metric_store2.all_values).to eq(
        {a: "x", b: "x"} => 3.0,
      )
    end

    it "exports values correctly from multiple processes" do
      metric_store1.increment(labels: {a: "x", b: "x"}, by: 1)
      metric_store1.increment(labels: {a: "x", b: "zzz"}, by: 2)
      metric_store2.increment(labels: {a: "x", b: "x"}, by: 3)

      # 2nd process
      allow(Process).to receive(:pid).and_return(23456)
      metric_store1.increment(labels: {a: "x", b: "x"}, by: 4)
      metric_store1.increment(labels: {a: "x", b: "yyy"}, by: 5)
      metric_store2.increment(labels: {a: "x", b: "x"}, by: 6)

      # Make sure we actually have 2 files to sup together
      expect(Dir.glob('/tmp/prometheus_test/metric___all_metrics___*').length).to eq(2)

      expect(metric_store1.all_values).to eq(
        {a: "x", b: "x"} => 5.0,
        {a: "x", b: "zzz"} => 2.0,
        {a: "x", b: "yyy"} => 5.0,
      )

      expect(metric_store2.all_values).to eq(
        {a: "x", b: "x"} => 9.0,
      )
    end

  end
end
