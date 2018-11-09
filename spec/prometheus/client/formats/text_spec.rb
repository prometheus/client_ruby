# encoding: UTF-8

require 'prometheus/client'
require 'prometheus/client/registry'
require 'prometheus/client/formats/text'

describe Prometheus::Client::Formats::Text do
  # Reset the data store
  before do
    Prometheus::Client.config.data_store = Prometheus::Client::DataStores::Synchronized.new
  end

  let(:registry) { Prometheus::Client::Registry.new }

  before do
    foo = registry.counter(:foo,
                           docstring: 'foo description',
                           labels: [:umlauts, :utf, :code],
                           preset_labels: {umlauts: 'Björn', utf: '佖佥'})
    foo.increment(labels: { code: 'red'}, by: 42)
    foo.increment(labels: { code: 'green'}, by: 3.14E42)
    foo.increment(labels: { code: 'blue'}, by: 1.23e-45)


    bar = registry.gauge(:bar,
                         docstring: "bar description\nwith newline",
                         labels: [:status, :code])
    bar.set(15, labels: { status: 'success', code: 'pink'})


    baz = registry.counter(:baz,
                           docstring: 'baz "description" \\escaping',
                           labels: [:text])
    baz.increment(labels: { text: "with \"quotes\", \\escape \n and newline" }, by: 15.0)


    qux = registry.summary(:qux,
                           docstring: 'qux description',
                           labels: [:for, :code],
                           preset_labels: { for: 'sake', code: '1' })
    92.times { qux.observe(0) }
    qux.observe(1243.21)


    xuq = registry.histogram(:xuq,
                             docstring: 'xuq description',
                             labels: [:code],
                             preset_labels: {code: 'ah'},
                             buckets: [10, 20, 30])
    xuq.observe(12)
    xuq.observe(3.2)
  end

  describe '.marshal' do
    it 'returns a Text format version 0.0.4 compatible representation' do
      expect(subject.marshal(registry)).to eql <<-'TEXT'
# TYPE foo counter
# HELP foo foo description
foo{umlauts="Björn",utf="佖佥",code="red"} 42.0
foo{umlauts="Björn",utf="佖佥",code="green"} 3.14e+42
foo{umlauts="Björn",utf="佖佥",code="blue"} 1.23e-45
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
