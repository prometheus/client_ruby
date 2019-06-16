# frozen_string_literal: true

require "prometheus/client"

describe Prometheus::Client::Tracer do
  subject(:tracer) { described_class.new }
  let(:metric) do
    Prometheus::Client::Counter.new(:counter, docstring: "example", labels: %i[worker])
  end

  describe ".trace" do
    # These tests try stubbing timing logic. Instead of using let's, we use a test
    # instance variable @now to represent the current time, as returned by a monotonic
    # clock system call.
    #
    # The #monotonic_now method of the tracer is stubbed to always return the current
    # value of @now, and tests can manipulate time by advancing that instance variable.
    #
    # The tracer is normally passed a block that manipulates @now.
    subject(:trace) { tracer.trace(metric, labels, &trace_block) }
    let(:labels) { { worker: 1 } }
    let(:trace_block) { -> { @now += 1.0 } }

    before do
      @now = 0.0 # set initial time
      allow(tracer).to receive(:monotonic_now) { @now }
    end

    it "increments metric with elapsed duration" do
      expect { trace }.to change { metric.values[labels] }.by(1.0)
    end

    context "when .collect is called during a trace" do
      let(:latch) { Mutex.new }
      let(:trace_block) do
        -> { latch.synchronize { @now += 1.0 } }
      end

      it "increments metric with incremental duration" do
        latch.lock # acquire the lock, trace should now block
        trace_thread = Thread.new do
          trace # will block until latch is released
        end

        # We need to block until the trace_thread has actually begun, otherwise we'll
        # never be able to guarantee the trace was started at now = 0.0, even if this
        # should happen almost immediately.
        Timeout.timeout(1) { sleep(0.01) until tracer.collect.size > 0 }

        # Advance the clock by 0.5s
        @now += 0.5

        # If we now collect, the metric should be incremented by the elapsed time (0.5s)
        expect { tracer.collect }.to change { metric.values[labels] }.by(0.5)

        # Collect once more should leave the metric unchanged, as no time has passed since
        # the last collect
        expect { tracer.collect }.to change { metric.values[labels] }.by(0.0)

        # Unlocking the latch and allowing the trace thread to complete will execute the
        # final part of a trace, which should update the metric with time elapsed. The
        # trace thread advances time by 1s right before it ends, so we expect to update
        # the metric by 1s.
        #
        # A bug would be if we incremented the metric by the time since our trace started
        # and when it ended, which in total is 1.5s. This would suggest we never reset the
        # trace clock when calling collect.
        expect {
          latch.unlock
          trace_thread.join(1)
          trace_thread.kill # in case thread misbehaves
        }.to change { metric.values[labels] }.by(1.0)
      end
    end
  end
end
