$: << File.expand_path('../../lib', File.dirname(__FILE__))

require 'rack'
require 'prometheus/client/rack/collector'
require 'prometheus/client/rack/exporter'

use Prometheus::Client::Rack::Exporter
use Prometheus::Client::Rack::Collector
run lambda { |env| [200, {'Content-Type' => 'text/html'}, ['OK']] }
