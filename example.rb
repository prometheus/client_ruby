$LOAD_PATH.unshift("./lib")

require 'prometheus/client'
require 'prometheus/client/formats/text.rb'

prometheus = Prometheus::Client.registry

counter = Prometheus::Client::Counter.new(:counter, 'Example counter')
gauge = Prometheus::Client::Gauge.new(:gauge, 'Example gauge')
histogram = Prometheus::Client::Histogram.new(:histogram, 'Example histogram', {}, [0, 1, 2])
summary = Prometheus::Client::Histogram.new(:summary, 'Example summary', {})
prometheus.register(counter)
prometheus.register(gauge)
prometheus.register(histogram)
prometheus.register(summary)

counter.increment({'foo': 'bar'}, 2)
counter.increment({'foo': 'biz'}, 4)
gauge.set({'foo': 'bar'}, 3)
gauge.set({'foo': 'biz'}, 3)
histogram.observe({'foo': 'bar'}, 0.5)
histogram.observe({'foo': 'biz'}, 0.5)
histogram.observe({'foo': 'bar'}, 1.5)
histogram.observe({'foo': 'biz'}, 2)
summary.observe({'foo': 'bar'}, 0.5)
summary.observe({'foo': 'biz'}, 0.5)
summary.observe({'foo': 'bar'}, 1.5)
summary.observe({'foo': 'biz'}, 2)

puts Prometheus::Client::Formats::Text.marshal(prometheus)
