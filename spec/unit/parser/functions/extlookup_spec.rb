#!/usr/bin/env rspec
require 'tempfile'
require 'spec_helper'

describe "the extlookup function" do
  include PuppetSpec::Files

  before :all do
    Puppet::Parser::Functions.autoloader.loadall
  end

  before :each do
    @scope = Puppet::Parser::Scope.new
    @scope.stubs(:environment).returns(Puppet::Node::Environment.new('production'))
  end

  it "should exist" do
    Puppet::Parser::Functions.function("extlookup").should == "function_extlookup"
  end

  it "should raise a ParseError if there is less than 1 arguments" do
    lambda { @scope.function_extlookup([]) }.should( raise_error(Puppet::ParseError))
  end

  it "should raise a ParseError if there is more than 3 arguments" do
    lambda { @scope.function_extlookup(["foo", "bar", "baz", "gazonk"]) }.should( raise_error(Puppet::ParseError))
  end

  it "should return the default" do
    result = @scope.function_extlookup([ "key", "default"])
    result.should == "default"
  end

  it "should lookup the key in a supplied datafile" do
    dir = tmpdir('extlookup_datadir')
    @scope.stubs(:lookupvar).with('::extlookup_datadir').returns(dir)
    @scope.stubs(:lookupvar).with('::extlookup_precedence').returns([])
    t = Tempfile.new(['extlookup','.csv'])
    t.puts 'key,value'
    t.puts 'nonkey,nonvalue'
    t.close
    result = @scope.function_extlookup([ "key", "default", t.path])
    result.should == "value"
    t.unlink
  end

  it "should return an array if the datafile contains more than two columns" do
    dir = tmpdir('extlookup_datadir')
    @scope.stubs(:lookupvar).with('::extlookup_datadir').returns(dir)
    @scope.stubs(:lookupvar).with('::extlookup_precedence').returns([])
    t = Tempfile.new(['extlookup','.csv'])
    t.puts 'key,value1,value2'
    t.puts 'nonkey,nonvalue,nonvalue'
    t.close
    result = @scope.function_extlookup([ "key", "default", t.path])
    result.should =~ ["value1", "value2"]
    t.unlink
  end

  it "should raise an error if there's no matching key and no default" do
    dir = tmpdir('extlookup_datadir')
    @scope.stubs(:lookupvar).with('::extlookup_datadir').returns(dir)
    @scope.stubs(:lookupvar).with('::extlookup_precedence').returns([])
    t = Tempfile.new(['extlookup','.csv'])
    t.puts 'nonkey,nonvalue'
    t.close
    lambda { @scope.function_extlookup([ "key", nil, t.path]) }.should( raise_error(Puppet::ParseError))
    t.unlink
  end

  describe "should look in $extlookup_datadir for data files listed by $extlookup_precedence" do
    before do
      dir = tmpdir('extlookup_datadir')
      @scope.stubs(:lookupvar).with('::extlookup_datadir').returns(dir)
      File.open(File.join(dir, "one.csv"),"w"){ |one| one.puts "key,value1" }
      File.open(File.join(dir, "two.csv"),"w") do |two|
        two.puts "key,value2"
        two.puts "key2,value_two"
      end
      @scope.stubs(:lookupvar).with('::extlookup_precedence').returns(["one","two"])
    end

    it "when the key is in the first file" do
      result = @scope.function_extlookup([ "key" ])
      result.should == "value1"
    end

    it "when the key is in the second file" do
      result = @scope.function_extlookup([ "key2" ])
      result.should == "value_two"
    end

    it "should not modify extlookup_precedence data" do
      variable = '%{fqdn}'
      @scope.stubs(:lookupvar).with('::extlookup_precedence').returns([variable,"one"])
      @scope.stubs(:lookupvar).with('::fqdn').returns('myfqdn')
      result = @scope.function_extlookup([ "key" ])
      result.should be_a_kind_of(String)
      variable.should == '%{fqdn}'
    end

  end

  describe "should read yaml files in precedence to csv files" do
    before do
      dir = tmpdir('extlookup_datadir')
      @scope.stubs(:lookupvar).with('::extlookup_datadir').returns(dir)
      File.open(File.join(dir, "three.yaml"), "w") { |three| three.puts "key3: value_three" }
      File.open(File.join(dir, "three.csv"), "w") { |notthree| notthree.puts "key3,value3" }
    end

    it "reads the yaml" do
      @scope.stubs(:lookupvar).with('::extlookup_precedence').returns(["three"])
      result = @scope.function_extlookup([ "key3" ])
      result.should == "value_three"
    end
  end

  it "should return an array if the yaml file contains an array" do
    dir = tmpdir('extlookup_datadir')
    @scope.stubs(:lookupvar).with('::extlookup_datadir').returns(dir)
    @scope.stubs(:lookupvar).with('::extlookup_precedence').returns([])
    t = Tempfile.new(['extlookup','.yaml'])
    t.puts 'key:'
    t.puts '  - value1'
    t.puts '  - value2'
    t.puts 'nonkey:'
    t.puts '  - nonvalue1'
    t.puts '  - nonvalue2'
    t.close
    result = @scope.function_extlookup([ "key", "default", t.path])
    result.should =~ ["value1", "value2"]
    t.unlink
  end

  it "should return a hash if the yaml file contains a hash" do
    dir = tmpdir('extlookup_datadir')
    @scope.stubs(:lookupvar).with('::extlookup_datadir').returns(dir)
    @scope.stubs(:lookupvar).with('::extlookup_precedence').returns([])
    t = Tempfile.new(['extlookup','.yaml'])
    t.puts 'key:'
    t.puts '  v1: value1'
    t.puts '  v2: value2'
    t.puts 'nonkey:'
    t.puts '  nv1: nonvalue1'
    t.puts '  nv2: nonvalue2'
    t.close
    result = @scope.function_extlookup([ "key", "default", t.path])
    result.should be_a_kind_of(Hash)
    result.should have_key('v1')
    result.should have_key('v2')
    result.should have(2).items
    result.should include('v1'=>'value1', 'v2'=>'value2')
    t.unlink
  end

  it "should return expanded variables in yaml array values" do
    dir = tmpdir('extlookup_datadir')
    @scope.stubs(:lookupvar).with('::extlookup_datadir').returns(dir)
    @scope.stubs(:lookupvar).with('::extlookup_precedence').returns([])
    t = Tempfile.new(['vary','.yaml'])
    t.puts 'key:'
    t.puts '  - "%{foobar}"'
    t.puts '  - "val%{foobar}ue"'
    t.puts 'nonkey: nonvalue'
    t.close
    @scope.stubs(:lookupvar).with('foobar').returns('myfoobar')
    result = @scope.function_extlookup([ "key", "default", t.path])
    result.should =~ ['myfoobar','valmyfoobarue']
    t.unlink
  end
 
  it "should return expanded variables in yaml hash values" do
    dir = tmpdir('extlookup_datadir')
    @scope.stubs(:lookupvar).with('::extlookup_datadir').returns(dir)
    @scope.stubs(:lookupvar).with('::extlookup_precedence').returns([])
    t = Tempfile.new(['vary','.yaml'])
    t.puts 'key:'
    t.puts '  v1: "%{foobar}"'
    t.puts '  v2: "val%{foobar}ue"'
    t.puts 'nonkey: nonvalue'
    t.close
    @scope.stubs(:lookupvar).with('foobar').returns('myfoobar')
    result = @scope.function_extlookup([ "key", "default", t.path])
    result.should be_a_kind_of(Hash)
    result.should have_key('v1')
    result.should have_key('v2')
    result.should have(2).items
    result.should include('v1'=>'myfoobar', 'v2'=>'valmyfoobarue')
    t.unlink
  end
 
  it "should return expanded variables in yaml hash array values" do
    dir = tmpdir('extlookup_datadir')
    @scope.stubs(:lookupvar).with('::extlookup_datadir').returns(dir)
    @scope.stubs(:lookupvar).with('::extlookup_precedence').returns([])
    t = Tempfile.new(['vary','.yaml'])
    t.puts 'key:'
    t.puts '  v1:'
    t.puts '    - "before"'
    t.puts '    - "%{foobar}"'
    t.puts '    - "after"'
    t.puts '  v2:'
    t.puts 'nonkey: nonvalue'
    t.close
    @scope.stubs(:lookupvar).with('foobar').returns('myfoobar')
    result = @scope.function_extlookup([ "key", "default", t.path])
    result.should be_a_kind_of(Hash)
    result.should have_key('v1')
    result.should have_key('v2')
    result.should have(2).items
    result['v1'].should =~ ["before", "myfoobar", "after"]
    t.unlink
  end
 
  it "should unescape before parsing variables" do
    dir = tmpdir('extlookup_datadir')
    @scope.stubs(:lookupvar).with('::extlookup_datadir').returns(dir)
    @scope.stubs(:lookupvar).with('::extlookup_precedence').returns([])
    t = Tempfile.new(['vary','.yaml'])
    t.puts 'key: "\\x25{foobar}"'
    t.close
    @scope.stubs(:lookupvar).with('foobar').returns('myfoobar')
    result = @scope.function_extlookup([ "key", "default", t.path])
    result.should == 'myfoobar'
    t.unlink
  end
 
  it "should return expanded variables in yaml string values" do
    dir = tmpdir('extlookup_datadir')
    @scope.stubs(:lookupvar).with('::extlookup_datadir').returns(dir)
    @scope.stubs(:lookupvar).with('::extlookup_precedence').returns([])
    t = Tempfile.new(['vary','.yaml'])
    t.puts 'key: "%{foobar}"'
    t.close
    @scope.stubs(:lookupvar).with('foobar').returns('myfoobar')
    result = @scope.function_extlookup([ "key", "default", t.path])
    result.should == 'myfoobar'
    t.unlink
  end
 
  it "should return expanded variables in csv" do
    dir = tmpdir('extlookup_datadir')
    @scope.stubs(:lookupvar).with('::extlookup_datadir').returns(dir)
    @scope.stubs(:lookupvar).with('::extlookup_precedence').returns([])
    t = Tempfile.new(['vary','.csv'])
    t.puts 'key,%{foobar}'
    t.close
    @scope.stubs(:lookupvar).with('foobar').returns('myfoobar')
    result = @scope.function_extlookup([ "key", "default", t.path])
    result.should == 'myfoobar'
    t.unlink
  end

  it "should return a cached value from csv" do
    dir = tmpdir('extlookup_datadir')
    @scope.stubs(:lookupvar).with('::extlookup_datadir').returns(dir)
    @scope.stubs(:lookupvar).with('::extlookup_precedence').returns([])
    t = Tempfile.new(['extlookup','.csv'])
    t.puts 'key,value'
    t.puts 'nonkey,nonvalue'
    t.close
    result = @scope.function_extlookup([ "key", "default", t.path])
    result.should == "value"
    t.unlink
    result = @scope.function_extlookup([ "key", "default", t.path])
    result.should == "value"
  end
 
end
