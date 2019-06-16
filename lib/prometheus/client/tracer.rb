# frozen_string_literal: true

module Prometheus
  module Client
    # For metrics that track durations over the course of long-running tasks, we need to
    # ensure the metric is updated gradually while they execute instead of right at the
    # end. This class is used to track on-going 'traces', records of tasks starting and
    # stopping, and exposes a method `collect` that will update the associated metric with
    # the time elapsed since the last `collect`.
    class Tracer
      Trace = Struct.new(:metric, :labels, :time)

      def initialize
        @lock = Mutex.new
        @traces = []
      end

      # Start and manage the life of a trace. Pass a long-running block to this method to
      # ensure the associated metric is updated gradually throughout the execution.
      def trace(metric, labels = {})
        start(metric, labels)
        yield
      ensure
        stop(metric, labels)
      end

      # Update currently traced metrics- this will increment all on-going traces with the
      # delta of time between the last update and now. This should be called just before
      # serving a /metrics request.
      def collect(traces = @traces)
        @lock.synchronize do
          now = monotonic_now
          traces.each do |trace|
            time_since = [now - trace.time, 0].max
            trace.time = now
            trace.metric.increment(
              by: time_since,
              labels: trace.labels,
            )
          end
        end
      end

      private

      def start(metric, labels = {})
        @lock.synchronize { @traces << Trace.new(metric, labels, monotonic_now) }
      end

      def stop(metric, labels = {})
        matching = nil
        @lock.synchronize do
          matching, @traces = @traces.partition do |trace|
            trace.metric == metric && trace.labels == labels
          end
        end

        collect(matching)
      end

      # We're doing duration arithmetic which should make use of monotonic clocks, to
      # avoid changes to the system time from affecting our metrics.
      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
