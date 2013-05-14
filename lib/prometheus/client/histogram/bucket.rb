module Prometheus
  module Client
    class Histogram
      class Bucket
        attr_reader :observations

        def initialize
          @observations = 0
          @timings = []
        end

        def add(timing)
          # TODO: mutex
          @timmings << timing
        end
      end
    end
  end
end
