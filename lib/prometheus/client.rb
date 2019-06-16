# encoding: UTF-8

require 'prometheus/client/registry'
require 'prometheus/client/config'
require 'prometheus/client/tracer'

module Prometheus
  # Client is a ruby implementation for a Prometheus compatible client.
  module Client
    # Returns a default registry object
    def self.registry
      @registry ||= Registry.new
    end

    def self.config
      @config ||= Config.new
    end

    # Most people will want to use a global tracer instead of building their own, similar
    # to how most will use the global metrics registry.
    def self.tracer
      @tracer ||= Tracer.new
    end

    # Delegate to the Tracer.
    def self.trace(metric, labels = {}, &block)
      tracer.trace(metric, labels, &block)
    end
  end
end
