# encoding: UTF-8

require 'prometheus/client/data_stores/synchronized'

module Prometheus
  module Client
    class Config
      attr_accessor :data_store

      def initialize
        @data_store = Prometheus::Client::DataStores::Synchronized.new
      end
    end
  end
end
