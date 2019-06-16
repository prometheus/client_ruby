# frozen_string_literal: true

require "prometheus/client"
require "prometheus/middleware/trace_collector"

describe Prometheus::Middleware::TraceCollector do
  subject(:collector) { described_class.new(app, options) }

  let(:app) { double(call: []) }
  let(:options) { { tracer: tracer } }
  let(:tracer) { Prometheus::Client::Tracer.new }

  describe ".call" do
    subject(:call) { collector.call({}) }

    # The most basic of tests, just verifying the tracer is invoked. We rely on the tests
    # for the tracer to validate #collect works correctly.
    it "calls tracer.collect, then the original app" do
      expect(tracer).to receive(:collect).and_call_original
      expect(app).to receive(:call)

      call
    end
  end
end
