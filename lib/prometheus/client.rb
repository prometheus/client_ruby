require 'prometheus/client/registry'

module Prometheus
  module Client

    # Returns a default registry object
    def self.registry
      @@registry ||= Registry.new
    end

  end
end
