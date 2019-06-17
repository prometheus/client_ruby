# frozen_string_literal: true

require "prometheus/client"

describe Prometheus::Client do
  describe ".registry" do
    it "returns a registry object" do
      expect(described_class.registry).to be_a(Prometheus::Client::Registry)
    end

    it "memorizes the returned object" do
      expect(described_class.registry).to eql(described_class.registry)
    end
  end
end
