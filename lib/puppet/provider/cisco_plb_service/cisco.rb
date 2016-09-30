#
# The Cisco provider for cisco_plb_device_group.
#
# October 2016
#
# Copyright (c) 2016 Cisco and/or its affiliates.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'cisco_node_utils' if Puppet.features.cisco_node_utils?
begin
  require 'puppet_x/cisco/autogen'
rescue LoadError # seen on master, not on agent
  # See longstanding Puppet issues #4248, #7316, #14073, #14149, etc. Ugh.
  require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..',
                                     'puppet_x', 'cisco', 'autogen.rb'))
end

begin
  require 'puppet_x/cisco/cmnutils'
rescue LoadError # seen on master, not on agent
  # See longstanding Puppet issues #4248, #7316, #14073, #14149, etc. Ugh.
  require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..',
                                     'puppet_x', 'cisco', 'cmnutils.rb'))
end
Puppet::Type.type(:cisco_plb_service).provide(:cisco) do
  desc 'The Cisco provider for cisco_plb_service.'

  confine feature: :cisco_node_utils
  defaultfor operatingsystem: :nexus

  mk_resource_methods

  PLBSERVICE_NON_BOOL_PROPS = [
    :access_list,
    :device_group,
    :exclude_access_list,
    :load_bal_buckets,
    :load_bal_mask_pos,
    :load_bal_method_bundle_hash,
    :load_bal_method_bundle_select,
    :load_bal_method_end_port,
    :load_bal_method_proto,
    :load_bal_method_start_port,
    :peer_local,
  ]
  PLBSERVICE_BOOL_PROPS = [
    :fail_action,
    :load_bal_enable,
    :nat_destination,
  ]
  # shutdown property is treated separately due to the ordering.
  # When shutdown goes from true to false, it needs to be set
  # after all the other properties are set. For all other cases,
  # shutdown needs to be set first before any other
  # properties are set. Basically, no properties cannot be
  # changed while the service is active.
  PLBSERVICE_SHUT_PROP = [
    :shutdown
  ]
  PLBSERVICE_ARRAY_FLAT_PROPS = [
    :ingress_interface,
    :virtual_ip,
  ]
  PLBSERVICE_ALL_PROPS = PLBSERVICE_NON_BOOL_PROPS +
                         PLBSERVICE_ARRAY_FLAT_PROPS + PLBSERVICE_BOOL_PROPS
  PLBSERVICE_ALL_BOOL_PROPS = PLBSERVICE_BOOL_PROPS + PLBSERVICE_SHUT_PROP

  PuppetX::Cisco::AutoGen.mk_puppet_methods(:non_bool, self, '@nu',
                                            PLBSERVICE_NON_BOOL_PROPS)
  PuppetX::Cisco::AutoGen.mk_puppet_methods(:array_flat, self, '@nu',
                                            PLBSERVICE_ARRAY_FLAT_PROPS)
  PuppetX::Cisco::AutoGen.mk_puppet_methods(:bool, self, '@nu',
                                            PLBSERVICE_BOOL_PROPS)
  PuppetX::Cisco::AutoGen.mk_puppet_methods(:bool, self, '@nu',
                                            PLBSERVICE_SHUT_PROP)

  def initialize(value={})
    super(value)
    @nu = Cisco::PlbService.plbs[@property_hash[:name]]
    @property_flush = {}
  end

  def self.properties_get(plb_service_name, nu_obj)
    debug "Checking instance, #{plb_service_name}."
    current_state = {
      service_name: plb_service_name,
      name:         plb_service_name,
      ensure:       :present,
    }
    # Call node_utils getter for each property
    PLBSERVICE_NON_BOOL_PROPS.each do |prop|
      current_state[prop] = nu_obj.send(prop)
    end
    PLBSERVICE_ARRAY_FLAT_PROPS.each do |prop|
      current_state[prop] = nu_obj.send(prop)
    end
    PLBSERVICE_ALL_BOOL_PROPS.each do |prop|
      val = nu_obj.send(prop)
      if val.nil?
        current_state[prop] = nil
      else
        current_state[prop] = val ? :true : :false
      end
    end
    # nested array properties
    current_state[:ingress_interface] = nu_obj.ingress_interface
    current_state[:virtual_ip] = nu_obj.virtual_ip
    new(current_state)
  end # self.properties_get

  def self.instances
    plbs = []
    Cisco::PlbService.plbs.each do |plb_service_name, nu_obj|
      plbs << properties_get(plb_service_name, nu_obj)
    end
    plbs
  end

  def self.prefetch(resources)
    plbs = instances
    resources.keys.each do |name|
      provider = plbs.find { |nu_obj| nu_obj.instance_name == name }
      resources[name].provider = provider unless provider.nil?
    end
  end # self.prefetch

  def exists?
    (@property_hash[:ensure] == :present)
  end

  def create
    @property_flush[:ensure] = :present
  end

  def destroy
    @property_flush[:ensure] = :absent
  end

  def instance_name
    service_name
  end

  def service_shutdown?
    cur_shut = @property_hash[:shutdown]
    next_shut = @resource[:shutdown]
    !(cur_shut == :false && (next_shut.nil? || next_shut == :true))
  end

  def all_prop_set(new_plb)
    PLBSERVICE_ALL_PROPS.each do |prop|
      next unless @resource[prop]
      send("#{prop}=", @resource[prop]) if new_plb
      unless @property_flush[prop].nil?
        @nu.send("#{prop}=", @property_flush[prop]) if
          @nu.respond_to?("#{prop}=")
      end
    end
    # custom setters which require one-shot multi-param setters
    load_balance_set
  end

  def shut_prop_set(new_plb)
    PLBSERVICE_SHUT_PROP.each do |prop|
      next unless @resource[prop]
      send("#{prop}=", @resource[prop]) if new_plb
      unless @property_flush[prop].nil?
        @nu.send("#{prop}=", @property_flush[prop]) if
          @nu.respond_to?("#{prop}=")
      end
    end
  end

  def properties_set(new_plb=false)
    if new_plb || service_shutdown?
      all_prop_set(new_plb)
      shut_prop_set(new_plb)
    else
      shut_prop_set(new_plb)
      all_prop_set(new_plb)
    end
  end

  def ingress_interface=(should_list)
    should_list = @nu.default_ingress_interface if should_list[0] == :default
    @property_flush[:ingress_interface] = should_list
  end

  def virtual_ip=(should_list)
    should_list = @nu.default_virtual_ip if should_list[0] == :default
    @property_flush[:virtual_ip] = should_list
  end

  def load_balance_set
    attrs = {}
    vars = [
      :load_bal_buckets,
      :load_bal_mask_pos,
      :load_bal_method_bundle_hash,
      :load_bal_method_bundle_select,
      :load_bal_method_end_port,
      :load_bal_method_proto,
      :load_bal_method_start_port,
      :load_bal_enable,
    ]
    return unless vars.any? { |p| @property_flush.key?(p) }
    # At least one var has changed, get all vals from manifest
    vars.each do |p|
      if @resource[p] == :default
        attrs[p] = @nu.send("default_#{p}")
      else
        attrs[p] = @resource[p]
        attrs[p] = PuppetX::Cisco::Utils.bool_sym_to_s(attrs[p])
      end
    end
    @nu.load_balance_set(attrs)
  end

  def flush
    if @property_flush[:ensure] == :absent
      @nu.destroy
      @nu = nil
    else
      # Create/Update
      if @nu.nil?
        new_plb = true
        @nu = Cisco::PlbService.new(@resource[:service_name])
      end
      properties_set(new_plb)
    end
  end
end
