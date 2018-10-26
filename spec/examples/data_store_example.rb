# encoding: UTF-8

shared_examples_for Prometheus::Client::DataStores do
  describe "MetricStore#set and #get" do
    it "returns the value set for each labelset" do
      metric_store.set(labels: { foo: "bar" }, val: 5)
      metric_store.set(labels: { foo: "baz" }, val: 2)
      expect(metric_store.get(labels: { foo: "bar" })).to eq(5)
      expect(metric_store.get(labels: { foo: "baz" })).to eq(2)
      expect(metric_store.get(labels: { foo: "bat" })).to eq(0)
    end
  end

  describe "MetricStore#increment" do
    it "returns the value set for each labelset" do
      metric_store.set(labels: { foo: "bar" }, val: 5)
      metric_store.set(labels: { foo: "baz" }, val: 2)

      metric_store.increment(labels: { foo: "bar" })
      metric_store.increment(labels: { foo: "baz" }, by: 7)
      metric_store.increment(labels: { foo: "zzz" }, by: 3)

      expect(metric_store.get(labels: { foo: "bar" })).to eq(6)
      expect(metric_store.get(labels: { foo: "baz" })).to eq(9)
      expect(metric_store.get(labels: { foo: "zzz" })).to eq(3)
    end
  end

  describe "MetricStore#synchronize" do
    # I'm not sure it's possible to actually test that this synchronizes, but at least
    # it should run the passed block
    it "accepts a block and runs it" do
      a = 0
      metric_store.synchronize{ a += 1 }
      expect(a).to eq(1)
    end

    # This is just a safety check that we're not getting "nested transaction" issues
    it "allows modifying the store while in synchronized block" do
      metric_store.synchronize do
        metric_store.increment(labels: { foo: "bar" })
        metric_store.increment(labels: { foo: "baz" })
      end
    end
  end

  describe "MetricStore#all_values" do
    it "returns all specified labelsets, with their associated value" do
      metric_store.set(labels: { foo: "bar" }, val: 5)
      metric_store.set(labels: { foo: "baz" }, val: 2)

      expect(metric_store.all_values).to eq(
        { foo: "bar" } => 5.0,
        { foo: "baz" } => 2.0,
      )
    end
  end
end
