require 'yaml'
require 'csv'
require 'puppet/parser/opower'

module Puppet::Parser::Functions

  newfunction(:extlookup,
  :type => :rvalue,
  :doc => "This is a parser function to read data from external files, this version
supports CSV and YAML files but the concept can easily be adjusted for databases
or any other queryable data source. When both CSV and YAML versions of the same file 
exist, the YAML file takes precedence.

The object of this is to make it obvious when it's being used, rather than
magically loading data in when an module is loaded I prefer to look at the code
and see statements like:

    $snmp_contact = extlookup(\"snmp_contact\")

The above snippet will load the snmp_contact value from CSV files, this in its
own is useful but a common construct in puppet manifests is something like this:

    case $domain {
      \"myclient.com\": { $snmp_contact = \"John Doe <john@myclient.com>\" }
      default:        { $snmp_contact = \"My Support <support@my.com>\" }
    }

Over time there will be a lot of this kind of thing spread all over your manifests
and adding an additional client involves grepping through manifests to find all the
places where you have constructs like this.

This is a data problem and shouldn't be handled in code, a using this function you
can do just that.

First you configure it in site.pp:

    $extlookup_datadir = \"/etc/puppet/manifests/extdata\"
    $extlookup_precedence = [\"%{fqdn}\", \"domain_%{domain}\", \"common\"]

The array tells the code how to resolve values, first it will try to find it in
web1.myclient.com.csv then in domain_myclient.com.csv and finally in common.csv

Now create the following data files in /etc/puppet/manifests/extdata:

    domain_myclient.com.csv:
      snmp_contact,John Doe <john@myclient.com>
      root_contact,support@%{domain}
      client_trusted_ips,192.168.1.130,192.168.10.0/24

    common.csv:
      snmp_contact,My Support <support@my.com>
      root_contact,support@my.com

Now you can replace the case statement with the simple single line to achieve
the exact same outcome:

   $snmp_contact = extlookup(\"snmp_contact\")

The above code shows some other features, you can use any fact or variable that
is in scope by simply using %{varname} in your data files, you can return arrays
by just having multiple values in the csv after the initial variable name.

In the event that a variable is nowhere to be found a critical error will be raised
that will prevent your manifest from compiling, this is to avoid accidentally putting
in empty values etc.  You can however specify a default value:

   $ntp_servers = extlookup(\"ntp_servers\", \"1.${country}.pool.ntp.org\")

In this case it will default to \"1.${country}.pool.ntp.org\" if nothing is defined in
any data file.

You can also specify an additional data file to search first before any others at use
time, for example:

    $version = extlookup(\"rsyslog_version\", \"present\", \"packages\")
    package{\"rsyslog\": ensure => $version }

This will look for a version configured in packages.csv and then in the rest as configured
by $extlookup_precedence if it's not found anywhere it will default to `present`, this kind
of use case makes puppet a lot nicer for managing large amounts of packages since you do not
need to edit a load of manifests to do simple things like adjust a desired version number.

Precedence values can have variables embedded in them in the form %{fqdn}, you could for example do:

    $extlookup_precedence = [\"hosts/%{fqdn}\", \"common\"]

This will result in /path/to/extdata/hosts/your.box.com.csv being searched.

This is for back compatibility to interpolate variables with %. % interpolation is a workaround for a problem that has been fixed: Puppet variable interpolation at top scope used to only happen on each run.") do |args|

    # Use two-level caching. The first cache is for each of the opower_lookup functions, the
    # second cache is for extlookup itself, as there is no need to defer to the second-order
    # cache if we have already looked up key once. A cache miss in opower_extlookup_cache yields
    # population of opower_lookup_cache. We can share cache between each of the functions because
    # we enforce strict file naming conventions.
    # There is no need to cache negatives, since we always cache a value (found value or default)
    # as failure to find a value raises an exception.

    cache = Puppet::Parser::Opower.cache(host)
    opower_lookup_cache = cache.lookup
    opower_extlookup_cache = cache.extlookup

    substitute_variables = lambda { |val|
      case val
      when String
        # parse %{}'s in the string into local variables using lookupvar()
        while val =~ /%\{(.+?)\}/
          val.gsub!(/%\{#{$1}\}/, lookupvar($1))
        end
        val
      when Array
        val.map { |v| substitute_variables.call(v) }
      when Hash
        val.each_key { |k| val[k] = substitute_variables.call(val[k]) }
      else
        val
      end
    }

    lookup_csv = lambda { |key, file|
      opower_lookup_cache[file] ||= CSV.read(file)
      result = opower_lookup_cache[file].find { |csv_key, _| csv_key == key }

      # return just the single result if there's just one,
      # else take all the fields in the csv and build an array
      if result
        if result.length == 2
          substitute_variables.call(result[1].to_s)
        elsif result.length > 1
          # Individual cells in a CSV result are a weird data type and throws
          # puppet's yaml parsing, so just map it all to plain old strings
          result[1..-1].map do |v|
            v = substitute_variables.call(v)
          end
        end
      end
    }

    lookup_yaml = lambda { |key, file|
      opower_lookup_cache[file] ||= YAML.load_file(file)
      y = opower_lookup_cache[file]
      substitute_variables.call(y[key]) if y.has_key?(key)
    }

    csv_extension = 'csv'
    yaml_extension = 'yaml'
    
    (key, default, datafile) = args

    raise Puppet::ParseError, ("extlookup(): wrong number of arguments (#{args.length}; must be <= 3)") if args.length > 3

    return opower_extlookup_cache[key] if opower_extlookup_cache.has_key?(key)
   
    supported_extensions = [ yaml_extension, csv_extension ]

    extlookup_datadir = undef_as('',lookupvar('::extlookup_datadir'))

    # retrieve values in extlookup_precedence (e.g. from site.pp) and 
    # perform variable interpolation on each of the paths returned
    extlookup_precedence = undef_as([],lookupvar('::extlookup_precedence')).map { |var| var.gsub(/%\{(.+?)\}/) { lookupvar("::#{$1}") } }

    datafiles = []

    datafiles = extlookup_precedence.map do |d|
      location = [extlookup_datadir, d].join('/')
      extension = supported_extensions.find { |ext| File.exists?("#{location}.#{ext}") }
      "#{location}.#{extension}" if extension
    end.reject(&:nil?)

    # if we got a custom data file, add it to the front of the list of places to look
    if !datafile.nil? && File.exists?(datafile)
      datafiles = [datafile] + datafiles
    end

    desired = nil

    datafiles.each do |file|
      unless desired
        desired = case file.split('.').last.downcase
                  when csv_extension
                    lookup_csv.call(key, file)
                  when yaml_extension
                    lookup_yaml.call(key, file)
                  end
      end
    end

    opower_extlookup_cache[key] = desired || default or raise Puppet::ParseError, "No match found for '#{key}' in any data file during extlookup()"

  end
end
