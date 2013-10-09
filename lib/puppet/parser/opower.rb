module Puppet::Parser
  class Opower

    class Cache
      attr_reader :lookup, :extlookup

      def initialize
        @lookup = {}
        @extlookup = {}
      end
    end

    def self.cache(key)
      @@cache ||= {}
      @@cache[key] ||= Cache.new
    end

    def self.delete(key)
      @@cache.delete(key) if @@cache
    end

  end
end
