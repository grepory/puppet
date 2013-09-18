require 'csv'

module Puppet::Parser::Functions
  newfunction(:extlookup,
  :type => :rvalue,
  :doc => "This is a parser function to read data from external files, this version
supports CSV and YAML files but the concept can easily be adjust for databases
or any other queryable data source. When both a CSV and YAML file exist, always prefer
the YAML.

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

    key = args[0]

    default  = args[1]
    datafile = args[2]

    raise Puppet::ParseError, ("extlookup(): wrong number of arguments (#{args.length}; must be <= 3)") if args.length > 3

    supported_extensions = [ 'yaml', 'csv' ]

    extlookup_datadir = undef_as('',lookupvar('::extlookup_datadir'))

    extlookup_precedence = undef_as([],lookupvar('::extlookup_precedence')).collect { |var| var.gsub(/%\{(.+?)\}/) { lookupvar("::#{$1}") } }

    datafiles = []

    # if we got a custom data file, add it to the front of the list of places to look
    unless "#{datafile}".empty?
      extlookup_precedence.unshift(datafile)
    end

    extlookup_precedence.each do |d|
      datafiles << extlookup_datadir + "/#{d}"
    end

    desired = nil

    datafiles.each do |datafile|
      if desired.nil?
        extension = supported_extensions.find { |ext| File.exists?("#{datafile}.#{ext}") }
        next unless extension
        file = "#{datafile}.#{extension}"

        if extension == 'csv'
          result = CSV.read(file).find { |r| r[0] == key }

          # return just the single result if theres just one,
          # else take all the fields in the csv and build an array
          if result
            if result.length == 2
              val = result[1].to_s

              # parse %{}'s in the CSV into local variables using lookupvar()
              while val =~ /%\{(.+?)\}/
                val.gsub!(/%\{#{$1}\}/, lookupvar($1))
              end
              desired = val
            elsif result.length > 1
              (csv_key, *cells) = result

              # Individual cells in a CSV result are a weird data type and throws
              # puppets yaml parsing, so just map it all to plain old strings
              cells.map do |v|
                while v =~ /%\{(.+?)\}/
                  v.gsub!(/%\{#{$1}\}/, lookupvar($1))
                end
              end
              desired = cells
            end
          end
        elsif extension == 'yaml'
          y = YAML.load_file(file)
          desired = y[key] if y.has_key?(key)
        end
      end
    end

    desired || default or raise Puppet::ParseError, "No match found for '#{key}' in any data file during extlookup()"

  end
end
