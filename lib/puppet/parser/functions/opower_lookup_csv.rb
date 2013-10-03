require 'csv'

module Puppet::Parser::Functions
  newfunction(:opower_lookup_csv,
              :type => :rvalue,
              :doc => "Helper function for new extlookup that parses CSV and then
returns the first-matching value for a key. 

Arguments:
key  - CSV key to find
file - File in which to search for the key") do |args|

    (key, file) = args

    raise Puppet::ParseError, "opower_lookup_csv: wrong number of arguments (#{args.length}; must be = 2" if args.length != 2

    Puppet::Parser::Functions.autoloader.loadall

    @opower_lookup_cache[file] ||= CSV.read(file)
    result = @opower_lookup_cache[file].find { |csv_key, _| csv_key == key }

    # return just the single result if there's just one,
    # else take all the fields in the csv and build an array
    if result
      if result.length == 2
        function_substitute_variables([result[1].to_s])
      elsif result.length > 1
        # Individual cells in a CSV result are a weird data type and throws
        # puppet's yaml parsing, so just map it all to plain old strings
        result[1..-1].map do |v|
          v = function_substitute_variables([v])
        end
      end
    end
  end
end
