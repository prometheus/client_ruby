# encoding: UTF-8

require 'prometheus/client/registry'

module Prometheus
  # Client is a ruby implementation for a Prometheus compatible client.
  module Client
    # Returns a default registry object
    def self.registry
      @registry ||= Registry.new
    end
  end
end
