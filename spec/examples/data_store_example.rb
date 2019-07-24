# encoding: UTF-8

# NOTE: Do not change instances of `eql` to `eq` in this file.
#
# The interface of a store is a labelset (hash of hashes) to a double. It's important
# that we check the values are doubles rather than integers. `==`, which is what `eq`
# calls allows conversion between floats and integers (i.e. `5 == 5.0`). `eql` enforces
# that the two numbers are of the same type.
shared_examples_for Prometheus::Client::DataStores do
  describe "MetricStore#set and #get" do
    it "returns the value set for each labelset" do
      expect(metric_store.get(labels: { foo: "bar" })).to eql(0.0)
    end
  end

  describe "MetricStore#set and #get" do
    it "returns the value set for each labelset" do
      metric_store.set(labels: { foo: "bar" }, val: 5)
      metric_store.set(labels: { foo: "baz" }, val: 2)
      expect(metric_store.get(labels: { foo: "bar" })).to eql(5.0)
      expect(metric_store.get(labels: { foo: "baz" })).to eql(2.0)
      expect(metric_store.get(labels: { foo: "bat" })).to eql(0.0)
    end
  end

  describe "MetricStore#increment" do
    it "returns the value set for each labelset" do
      metric_store.set(labels: { foo: "bar" }, val: 5)
      metric_store.set(labels: { foo: "baz" }, val: 2)

      metric_store.increment(labels: { foo: "bar" })
      metric_store.increment(labels: { foo: "baz" }, by: 7)
      metric_store.increment(labels: { foo: "zzz" }, by: 3)

      expect(metric_store.get(labels: { foo: "bar" })).to eql(6.0)
      expect(metric_store.get(labels: { foo: "baz" })).to eql(9.0)
      expect(metric_store.get(labels: { foo: "zzz" })).to eql(3.0)
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

      expect(metric_store.all_values).to eql(
        { foo: "bar" } => 5.0,
        { foo: "baz" } => 2.0,
      )
    end

    context "for a combination of labels that hasn't had a value set" do
      it "returns 0.0" do
        expect(metric_store.all_values[{ foo: "bar" }]).to eql(0.0)
      end
    end
  end
end
