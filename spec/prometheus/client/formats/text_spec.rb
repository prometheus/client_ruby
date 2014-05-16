# encoding: UTF-8

require 'prometheus/client/formats/text'

describe Prometheus::Client::Formats::Text do
  let(:registry) do
    double(metrics: [
      double(
        name: :foo,
        docstring: 'foo description',
        base_labels: {},
        type: :counter,
        values: { { code: 'red' } => 42 },
      ),
      double(
        name: :bar,
        docstring: "bar description\nwith newline",
        base_labels: { status: 'success' },
        type: :gauge,
        values: { { code: 'pink' } => 15 },
      ),
      double(
        name: :baz,
        docstring: 'baz "description" \\escaping',
        base_labels: {},
        type: :counter,
        values: { { text: %Q(with "quotes", \\escape \n and newline) } => 15 },
      ),
      double(
        name: :qux,
        docstring: 'qux description',
        base_labels: { for: 'sake' },
        type: :summary,
        values: { { code: '1' } => { 0.5 => 4.2, 0.9 => 8.32, 0.99 => 15.3 } },
      ),
    ],)
  end

  describe '.marshal' do
    it 'returns a Text format version 0.0.4 compatible representation' do
      expect(subject.marshal(registry)).to eql <<-'TEXT'
# TYPE foo counter
# HELP foo foo description
foo{code="red"} 42
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
      TEXT
    end
  end
end
