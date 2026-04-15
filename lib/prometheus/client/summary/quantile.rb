# encoding: UTF-8

module Prometheus
  module Client
    module Quantile
      Sample = Struct.new(:value, :width, :delta)

      BUFFER_SIZE = 500

      class Estimator
        attr_reader :observations

        def initialize(objectives)
          @objectives = objectives
          @buffer = []
          @samples = []
          @observations = 0
        end

        def observe(value)
          @buffer << value
          @observations += 1
          flush if @buffer.size >= BUFFER_SIZE
        end

        def query(quantile)
          flush unless @buffer.empty?
          return Float::NAN if @samples.empty?

          desired = quantile * @observations
          cumulative = 0

          @samples.each_with_index do |sample, i|
            cumulative += sample.width
            if i == @samples.size - 1
              return sample.value
            end

            upper = desired + (allowable_error(desired) / 2.0)
            if cumulative + @samples[i + 1].delta > upper
              return sample.value
            end
          end

          @samples.last.value
        end

        def flush
          return if @buffer.empty?

          @buffer.sort!
          merge(@buffer)
          @buffer.clear
          compress
        end

        def reset
          @buffer.clear
          @samples.clear
          @observations = 0
        end

        private

        def merge(sorted_values)
          if @samples.empty?
            sorted_values.each do |v|
              @samples << Sample.new(v, 1, 0)
            end
            return
          end

          merged = []
          sample_idx = 0
          value_idx = 0
          cumulative = 0

          while sample_idx < @samples.length && value_idx < sorted_values.length
            s = @samples[sample_idx]

            if sorted_values[value_idx] <= s.value
              v = sorted_values[value_idx]
              value_idx += 1

              if merged.empty?
                merged << Sample.new(v, 1, 0)
              else
                delta = compute_delta(cumulative + 1)
                merged << Sample.new(v, 1, delta)
              end
            else
              cumulative += s.width
              merged << s
              sample_idx += 1
            end
          end

          while sample_idx < @samples.length
            merged << @samples[sample_idx]
            sample_idx += 1
          end

          while value_idx < sorted_values.length
            v = sorted_values[value_idx]
            value_idx += 1
            if merged.empty?
              merged << Sample.new(v, 1, 0)
            else
              merged << Sample.new(v, 1, 0)
            end
          end

          @samples = merged
        end

        def compress
          return if @samples.size < 3

          i = @samples.size - 2
          cumulative = @samples.last.width

          while i >= 1
            s = @samples[i]
            next_s = @samples[i + 1]
            cumulative_at_i = @observations - cumulative

            if s.width + next_s.width + next_s.delta <= allowable_error(cumulative_at_i)
              next_s.width += s.width
              @samples.delete_at(i)
            end

            cumulative += s.width
            i -= 1
          end
        end

        def compute_delta(rank)
          return 0 if rank <= 1 || rank >= @observations
          allowable_error(rank).floor
        end

        def allowable_error(rank)
          n = @observations.to_f
          min_val = Float::INFINITY

          @objectives.each do |quantile, epsilon|
            if rank <= quantile * n
              err = (2.0 * epsilon * rank) / quantile
            else
              err = (2.0 * epsilon * (n - rank)) / (1.0 - quantile)
            end
            min_val = err if err < min_val
          end

          min_val
        end
      end

      class TimeWindowEstimator
        def initialize(objectives:, max_age: 600, age_buckets: 5)
          @objectives = objectives
          @max_age = max_age
          @age_buckets = age_buckets
          @streams = Array.new(age_buckets) { Estimator.new(objectives) }
          @rotation_interval = max_age.to_f / age_buckets
          @head = 0
          @last_rotation = current_time
        end

        def observe(value)
          rotate
          @streams.each { |s| s.observe(value) }
        end

        def query(quantile)
          rotate
          @streams[@head].flush
          @streams[@head].query(quantile)
        end

        def reset
          @streams.each(&:reset)
          @head = 0
          @last_rotation = current_time
        end

        private

        def rotate
          now = current_time
          elapsed = now - @last_rotation

          rotations = (elapsed / @rotation_interval).floor
          return if rotations < 1

          rotations = @age_buckets if rotations > @age_buckets

          rotations.times do
            @head = (@head + 1) % @age_buckets
            @streams[@head].reset
          end

          @last_rotation = now
        end

        def current_time
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
