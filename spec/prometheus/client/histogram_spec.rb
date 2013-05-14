require 'prometheus/client/histogram'
require 'prometheus/client/metric_example'

module Prometheus::Client
  describe Histogram do
    let(:gauge) { Histogram.new }

    it_behaves_like Metric do
      let(:default) { nil }
    end

    describe '#add' do
      it '' do

      end
    end

  end
end
