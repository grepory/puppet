module Puppet::Parser::Functions
  newfunction(:substitute_variables,
  :type => :rvalue,
  :doc => "substitutes a variable in another variable") do |args|
    val = args.first
    Puppet::Parser::Functions.autoloader.loadall
    # puts "val.class = #{val.class}"
    # puts "val.inspect = #{val.inspect}"
    case val
    when String
      # parse %{}'s in the CSV into local variables using lookupvar()
      while val =~ /%\{(.+?)\}/
        val.gsub!(/%\{#{$1}\}/, lookupvar($1))
      end
      val
    when Array
      val.map { |v| function_substitute_variables([v]) }
    when Hash
      val.each_key { |k| val[k] = function_substitute_variables([val[k]]) }
    else
      val
    end
  end
end
