###############################################################################
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
###############################################################################
#
# See README-develop-beaker-scripts.md (Section: Test Script Variable Reference)
# for information regarding:
#  - test script general prequisites
#  - command return codes
#  - A description of the 'tests' hash and its usage
#
###############################################################################

require File.expand_path('../../lib/utilitylib.rb', __FILE__)

# Test hash top-level keys
tests = {
  master:        master,
  agent:         agent,
  intf_type:     'ethernet',
  platform:      'n(7|9)k$',
  resource_name: 'cisco_plb_service',
}

# Skip -ALL- tests if a top-level platform/os key exludes this platform
skip_unless_supported(tests)

def find_ingress_ethernet_interface(tests)
  if tests[:ethernet]
    intf = tests[:ethernet]
  else
    intf = find_interface(tests)
    # cache for later tests
    tests[:ethernet] = intf
  end
  intf
end
@ingress_eth_int = find_ingress_ethernet_interface(tests)

# Test hash test cases
tests[:default] = {
  desc:           '1.1 Common Defaults',
  title_pattern:  'myService',
  manifest_props: {
    access_list:         'default',
    device_group:        'default',
    exclude_access_list: 'default',
    fail_action:         'default',
    ingress_interface:   'default',
    load_bal_enable:     'default',
    shutdown:            'default',
    virtual_ip:          'default',
  },
  code:           [0, 2],
  resource:       {
    fail_action:     'false',
    load_bal_enable: 'false',
    shutdown:        'true',
  },
}

tests[:default_plat] = {
  desc:           '1.2 Defaults',
  title_pattern:  'myService',
  manifest_props: {
    device_group:      'udpGroup',
    ingress_interface: 'default',
    nat_destination:   'default',
    peer_local:        'default',
  },
  code:           [0, 2],
  resource:       {
    'nat_destination' => 'false'
  },
}

ingress_intf = [['vlan2', '4.4.4.4'], [@ingress_eth_int, '5.5.5.5'], ['port-channel100', '6.6.6.6']]
vip = ['ip 3.3.3.3 255.0.0.0 tcp 500 advertise enable']

tests[:non_default] = {
  desc:           '2.1 Common Non Defaults',
  title_pattern:  'myService',
  manifest_props: {
    access_list:                   'iap',
    device_group:                  'udpGroup',
    exclude_access_list:           'eap',
    fail_action:                   'true',
    ingress_interface:             ingress_intf,
    load_bal_buckets:              '16',
    load_bal_enable:               'true',
    load_bal_mask_pos:             '5',
    load_bal_method_bundle_hash:   'ip-l4port',
    load_bal_method_bundle_select: 'dst',
    load_bal_method_end_port:      '100',
    load_bal_method_proto:         'udp',
    load_bal_method_start_port:    '50',
    shutdown:                      'true',
  },
}

tests[:non_default_plat] = {
  desc:           '2.2 Non Defaults',
  title_pattern:  'myService',
  manifest_props: {
    device_group:                  'udpGroup',
    ingress_interface:             ingress_intf,
    load_bal_buckets:              '32',
    load_bal_enable:               'true',
    load_bal_mask_pos:             '10',
    load_bal_method_bundle_hash:   'ip',
    load_bal_method_bundle_select: 'src',
    nat_destination:               'true',
    peer_local:                    'plservice',
    shutdown:                      'false',
    virtual_ip:                    vip,
  },
}

tests[:non_default_shut] = {
  desc:           '3.1 Common create service and turn it on',
  title_pattern:  'myService',
  manifest_props: {
    device_group:      'udpGroup',
    ingress_interface: [[@ingress_eth_int, '2.2.2.2']],
    shutdown:          'false',
  },
}

tests[:non_default_shut_2] = {
  desc:           '3.2 Common change params and turn off service',
  title_pattern:  'myService',
  manifest_props: {
    device_group:      'udpGroup',
    ingress_interface: [[@ingress_eth_int, '3.3.3.3']],
    shutdown:          'true',
  },
}

tests[:non_default_shut_3] = {
  desc:           '3.3 Common change params and leave service off',
  title_pattern:  'myService',
  manifest_props: {
    device_group:      'udpGroup',
    ingress_interface: [[@ingress_eth_int, '4.4.4.4']],
    shutdown:          'true',
  },
}

tests[:non_default_shut_4] = {
  desc:           '3.4 Common change params and turn service back on',
  title_pattern:  'myService',
  manifest_props: {
    device_group:      'udpGroup',
    ingress_interface: [[@ingress_eth_int, '5.5.5.5']],
    shutdown:          'false',
  },
}

def cleanup(agent)
  cmds = ['no ip access-list iap',
          'no ip access-list eap',
          'no vlan 2',
          'no interface port-channel 100',
          'no feature interface-vlan',
          'no feature plb',
         ].join(' ; ')
  test_set(agent, cmds)
  interface_cleanup(agent, @ingress_eth_int)
end

def unsupported_properties(_tests, _id)
  unprops = []
  unprops << :nat_destination if platform[/n9k$/]
  unprops
end

# Overridden to properly handle dependencies for this test file.
def test_harness_dependencies(_tests, _id)
  cleanup(agent)

  cmd = [
    'feature plb',
    'feature interface-vlan',
    'ip access-list iap ; ip access-list eap',
    "interface #{@ingress_eth_int} ; no switchport",
    'vlan 2 ; interface vlan 2',
    'interface port-channel 100 ; no switchport',
    'plb l3-device-group udpGroup ; node ip 1.1.1.1',
  ].join(' ; ')
  test_set(agent, cmd)
end

#################################################################
# TEST CASE EXECUTION
#################################################################
test_name "TestCase :: #{tests[:resource_name]}" do
  teardown { cleanup(agent) }
  cleanup(agent)

  # -------------------------------------------------------------------
  logger.info("\n#{'-' * 60}\nSection 1. Default Property Testing")

  test_harness_run(tests, :default)
  test_harness_run(tests, :default_plat)

  id = :default
  tests[id][:desc] = '1.4 Common Defaults (absent)'
  tests[id][:ensure] = :absent
  test_harness_run(tests, id)

  # -------------------------------------------------------------------
  logger.info("\n#{'-' * 60}\nSection 2. Non Default Property Testing")

  test_harness_run(tests, :non_default)
  test_harness_run(tests, :non_default_plat)
  test_harness_run(tests, :non_default_shut)
  test_harness_run(tests, :non_default_shut_2)
  test_harness_run(tests, :non_default_shut_3)
  test_harness_run(tests, :non_default_shut_4)

  # -------------------------------------------------------------------
  skipped_tests_summary(tests)
end
logger.info("TestCase :: #{tests[:resource_name]} :: End")
