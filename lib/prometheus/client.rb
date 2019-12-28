# encoding: UTF-8

require 'prometheus/client/registry'
require 'prometheus/client/config'

module Prometheus
  # Client is a ruby implementation for a Prometheus compatible client.
  module Client
    # Returns a default registry object
    def self.registry(labels: [], preset_labels: {})
      @registry ||= Registry.new(labels: labels, preset_labels: preset_labels)
    end

    def self.config
      @config ||= Config.new
    end
  end
end
