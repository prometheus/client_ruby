# encoding: UTF-8

require 'prometheus/client/formats/text'

describe Prometheus::Client::Formats::Text do
  let(:summary_value) do
    { 0.5 => 4.2, 0.9 => 8.32, 0.99 => 15.3 }.tap do |value|
      allow(value).to receive_messages(sum: 1243.21, total: 93)
    end
  end

  let(:histogram_value) do
    { 10 => 1, 20 => 2, 30 => 2 }.tap do |value|
      allow(value).to receive_messages(sum: 15.2, total: 2)
    end
  end

  let(:registry) do
    metrics = [
      double(
        name: :foo,
        docstring: 'foo description',
        base_labels: { umlauts: 'Björn', utf: '佖佥' },
        type: :counter,
        values: {
          { code: 'red' }   => 42,
          { code: 'green' } => 3.14E42,
          { code: 'blue' }  => -1.23e-45,
        },
      ),
      double(
        name: :bar,
        docstring: "bar description\nwith newline",
        base_labels: { status: 'success' },
        type: :gauge,
        values: {
          { code: 'pink' } => 15,
        },
      ),
      double(
        name: :baz,
        docstring: 'baz "description" \\escaping',
        base_labels: {},
        type: :counter,
        values: {
          { text: "with \"quotes\", \\escape \n and newline" } => 15,
        },
      ),
      double(
        name: :qux,
        docstring: 'qux description',
        base_labels: { for: 'sake' },
        type: :summary,
        values: {
          { code: '1' } => summary_value,
        },
      ),
      double(
        name: :xuq,
        docstring: 'xuq description',
        base_labels: {},
        type: :histogram,
        values: {
          { code: 'ah' } => histogram_value,
        },
      ),
    ]
    double(metrics: metrics)
  end

  describe '.marshal' do
    it 'returns a Text format version 0.0.4 compatible representation' do
      expect(subject.marshal(registry)).to eql <<-'TEXT'
# TYPE foo counter
# HELP foo foo description
foo{umlauts="Björn",utf="佖佥",code="red"} 42
foo{umlauts="Björn",utf="佖佥",code="green"} 3.14e+42
foo{umlauts="Björn",utf="佖佥",code="blue"} -1.23e-45
# TYPE bar gauge
# HELP bar bar description\nwith newline
bar{status="success",code="pink"} 15
# TYPE baz counter
# HELP baz baz "description" \\escaping
baz{text="with \"quotes\", \\escape \n and newline"} 15
# TYPE qux summary
# HELP qux qux description
qux{for="sake",code="1",quantile="0.5"} 4.2
qux{for="sake",code="1",quantile="0.9"} 8.32
qux{for="sake",code="1",quantile="0.99"} 15.3
qux_sum{for="sake",code="1"} 1243.21
qux_count{for="sake",code="1"} 93
# TYPE xuq histogram
# HELP xuq xuq description
xuq{code="ah",le="10"} 1
xuq{code="ah",le="20"} 2
xuq{code="ah",le="30"} 2
xuq{code="ah",le="+Inf"} 2
xuq_sum{code="ah"} 15.2
xuq_count{code="ah"} 2
      TEXT
    end
  end
end
