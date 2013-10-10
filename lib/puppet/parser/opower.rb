# Puppet::Parser::Opower
#
# Author: Greg Poirier <greg.poirier@opower.com>
#
# Singleton two-layer cache machanism intended for use with a modified version
# of extlookup.
#
# Attributes:
# extlookup - Top-level cache used by extlookup
# lookup    - Second-level cache used by CSV and YAML search functions

module Puppet::Parser
  class Opower

    class Cache
      attr_reader :lookup, :extlookup

      def initialize
        @lookup = {}
        @extlookup = {}
      end
    end

    # cache
    #
    # Parameters:
    # key: cache you wish to retrieve
    #
    # E.g. cache = Puppet::Parser::Opower.cache('hostname.va.opower.it')
    def self.cache(key)
      @@cache ||= {}
      @@cache[key] ||= Cache.new
    end

    # delete
    #
    # Parameters:
    # key: cache you wish to delete
    def self.delete(key)
      @@cache.delete(key)
    end

  end
end
