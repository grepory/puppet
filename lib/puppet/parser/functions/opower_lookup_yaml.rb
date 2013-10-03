module Puppet::Parser::Functions
  newfunction(:opower_lookup_yaml,
  :type => :rvalue,
  :doc => "Lookup a value in a YAML file") do |args|

    (key, file) = args

    y = YAML.load_file(file)
    function_substitute_variables([y[key]]) if y.has_key?(key)
  end
end
