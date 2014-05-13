require 'prometheus/client/formats/json'

describe Prometheus::Client::Formats::JSON do
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
        docstring: 'bar description',
        base_labels: { status: 'success' },
        type: :gauge,
        values: { { code: 'pink' } => 15 },
      ),
    ])
  end

  describe '.marshal' do
    it 'returns a version 0.0.2 compatible JSON string' do
      expect(subject.marshal(registry)).to eql([
        {
          "baseLabels" => { "name" => "foo" },
          "docstring" => "foo description",
          "metric" => {
            "type" => "counter",
            "value" => [
              { "labels" => { "code"=>"red" }, "value" => 42 },
            ]
          }
        },
        {
          "baseLabels" => { "status" => "success", "name" => "bar" },
          "docstring" => "bar description",
          "metric" => {
            "type" => "gauge",
            "value" => [
              { "labels" => { "code" => "pink" }, "value" => 15 },
            ]
          }
        },
      ].to_json)
    end
  end
end
