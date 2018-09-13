# encoding: UTF-8

require 'prometheus/client/formats/text'

describe Prometheus::Client::Formats::Text do
  let(:summary_value) do
    Struct.new(:sum, :total).new(1243.21, 93.0)
  end

  let(:histogram_value) do
    { 10 => 1.0, 20 => 2.0, 30 => 2.0 }.tap do |value|
      allow(value).to receive_messages(sum: 15.2, total: 2.0)
    end
  end

  let(:registry) do
    metrics = [
      double(
        name: :foo,
        docstring: 'foo description',
        type: :counter,
        values: {
          { umlauts: 'Björn', utf: '佖佥', code: 'red' }   => 42.0,
          { umlauts: 'Björn', utf: '佖佥', code: 'green' } => 3.14E42,
          { umlauts: 'Björn', utf: '佖佥', code: 'blue' }  => -1.23e-45,
        },
      ),
      double(
        name: :bar,
        docstring: "bar description\nwith newline",
        type: :gauge,
        values: {
          { status: 'success', code: 'pink' } => 15.0,
        },
      ),
      double(
        name: :baz,
        docstring: 'baz "description" \\escaping',
        type: :counter,
        values: {
          { text: "with \"quotes\", \\escape \n and newline" } => 15.0,
        },
      ),
      double(
        name: :qux,
        docstring: 'qux description',
        type: :summary,
        values: {
          { for: 'sake', code: '1' } => summary_value,
        },
      ),
      double(
        name: :xuq,
        docstring: 'xuq description',
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
foo{umlauts="Björn",utf="佖佥",code="red"} 42.0
foo{umlauts="Björn",utf="佖佥",code="green"} 3.14e+42
foo{umlauts="Björn",utf="佖佥",code="blue"} -1.23e-45
# TYPE bar gauge
# HELP bar bar description\nwith newline
bar{status="success",code="pink"} 15.0
# TYPE baz counter
# HELP baz baz "description" \\escaping
baz{text="with \"quotes\", \\escape \n and newline"} 15.0
# TYPE qux summary
# HELP qux qux description
qux_sum{for="sake",code="1"} 1243.21
qux_count{for="sake",code="1"} 93.0
# TYPE xuq histogram
# HELP xuq xuq description
xuq_bucket{code="ah",le="10"} 1.0
xuq_bucket{code="ah",le="20"} 2.0
xuq_bucket{code="ah",le="30"} 2.0
xuq_bucket{code="ah",le="+Inf"} 2.0
xuq_sum{code="ah"} 15.2
xuq_count{code="ah"} 2.0
      TEXT
    end
  end
end
