require 'prometheus/client/gauge'
require 'prometheus/client/metric_example'

module Prometheus::Client
  describe Gauge do
    let(:gauge) { Gauge.new }

    it_behaves_like Metric do
      let(:default) { nil }
    end

  end
end
