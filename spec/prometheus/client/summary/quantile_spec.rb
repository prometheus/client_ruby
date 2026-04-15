# encoding: UTF-8

require 'prometheus/client/summary/quantile'

describe Prometheus::Client::Quantile do
  let(:objectives) { { 0.5 => 0.05, 0.9 => 0.01, 0.99 => 0.001 } }

  describe Prometheus::Client::Quantile::Estimator do
    let(:estimator) { described_class.new(objectives) }

    describe '#observe' do
      it 'records observations' do
        100.times { |i| estimator.observe(i) }
        expect(estimator.observations).to eq(100)
      end
    end

    describe '#query' do
      it 'returns NaN for empty estimator' do
        expect(estimator.query(0.5)).to be_nan
      end

      it 'returns the value for a single observation' do
        estimator.observe(42)
        expect(estimator.query(0.5)).to eq(42)
      end

      context 'with uniform distribution' do
        before do
          10_000.times { |i| estimator.observe(i) }
        end

        it 'estimates p50 within epsilon' do
          result = estimator.query(0.5)
          expect(result).to be_within(10_000 * 0.05 * 2).of(5_000)
        end

        it 'estimates p90 within epsilon' do
          result = estimator.query(0.9)
          expect(result).to be_within(10_000 * 0.01 * 2).of(9_000)
        end

        it 'estimates p99 within epsilon' do
          result = estimator.query(0.99)
          expect(result).to be_within(10_000 * 0.001 * 2).of(9_900)
        end
      end

      context 'with small number of observations' do
        before do
          [1, 2, 3, 4, 5].each { |v| estimator.observe(v) }
        end

        it 'returns reasonable p50' do
          result = estimator.query(0.5)
          expect(result).to be_between(2, 4)
        end

        it 'returns reasonable p99' do
          result = estimator.query(0.99)
          expect(result).to be_between(4, 5)
        end
      end
    end

    describe '#flush' do
      it 'flushes the buffer into samples' do
        10.times { |i| estimator.observe(i) }
        estimator.flush
        expect(estimator.query(0.5)).to be_between(3, 7)
      end
    end

    describe '#reset' do
      it 'clears all state' do
        100.times { |i| estimator.observe(i) }
        estimator.reset
        expect(estimator.observations).to eq(0)
        expect(estimator.query(0.5)).to be_nan
      end
    end
  end

  describe Prometheus::Client::Quantile::TimeWindowEstimator do
    let(:estimator) do
      described_class.new(objectives: objectives, max_age: 10, age_buckets: 5)
    end

    describe '#observe and #query' do
      it 'tracks observations' do
        1000.times { |i| estimator.observe(i) }
        result = estimator.query(0.5)
        expect(result).to be_within(1000 * 0.05 * 2).of(500)
      end

      it 'returns NaN with no observations' do
        expect(estimator.query(0.5)).to be_nan
      end
    end

    describe '#reset' do
      it 'clears all state' do
        100.times { |i| estimator.observe(i) }
        estimator.reset
        expect(estimator.query(0.5)).to be_nan
      end
    end
  end
end
