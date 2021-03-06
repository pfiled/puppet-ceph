# Configure a ceph mon
#
# == Name
#   This resource's name is the mon's id and must be numeric.
# == Parameters
# [*fsid*] The cluster's fsid.
#   Mandatory. Get one with `uuidgen -r`.
#
# [*mon_secret*] The cluster's mon's secret key.
#   Mandatory. Get one with `ceph-authtool /dev/stdout --name=mon. --gen-key`.
#
# [*auth_type*] Auth type.
#   Optional. undef or 'cephx'. Defaults to 'cephx'.
#
# [*mon_data*] Base path for mon data. Data will be put in a mon.$id folder.
#   Optional. Defaults to '/var/lib/ceph.
#
# [*mon_port*] The mon's port.
#   Optional. Defaults to 6789.
#
# [*mon_addr*] The mon's address.
#   Optional. Defaults to the $ipaddress fact.
#
# == Dependencies
#
# none
#
# == Authors
#
#  François Charlier francois.charlier@enovance.com
#
# == Copyright
#
# Copyright 2012 eNovance <licensing@enovance.com>
#
define ceph::mon (
  $fsid,
  $monitor_secret,
  $auth_type = 'cephx',
  $mon_data = '/var/lib/ceph',
  $mon_port = 6789,
  $mon_addr = $ipaddress
) {

  if ! defined(Class['ceph::package']) {
    class { 'ceph::package': }
  }

  $mon_data_expanded = "${mon_data}/mon.${name}"

  file { $mon_data_expanded:
    ensure  => directory,
    owner   => 'root',
    group   => 0,
    mode    => '0755',
  }

  #FIXME: monitor_secret will appear in "ps" output …
  exec { 'ceph-mon-keyring':
    command => "ceph-authtool /var/lib/ceph/tmp/keyring.mon.${name} \
--create-keyring \
--name=mon. \
--add-key='${monitor_secret}' \
--cap mon 'allow *'",
    creates => "/var/lib/ceph/tmp/keyring.mon.${name}",
    before  => Exec['ceph-mon-mkfs'],
    require => Package['ceph'],
  }

  exec { 'ceph-mon-mkfs':
    command => "ceph-mon --mkfs -i ${name} \
--keyring /var/lib/ceph/tmp/keyring.mon.${name}",
    creates => "${mon_data_expanded}/keyring",
    before  => [
      Exec['ceph-admin-key'],
      #Exec['ceph-osd-bootstrap-key'],
      Service["ceph-mon.${name}"],
    ],
    require => [Package['ceph'], File['/etc/ceph/ceph.conf']],
  }

  service { "ceph-mon.${name}":
    ensure  => running,
    start   => "service ceph start mon.${name}",
    stop    => "service ceph stop mon.${name}",
    status  => "service ceph status mon.${name}",
    require => Exec['ceph-mon-mkfs'],
  }

  exec { 'ceph-admin-key':
    command => "ceph-authtool /etc/ceph/keyring \
--create-keyring \
--name=client.admin \
--add-key \
$(ceph --name mon. --keyring ${mon_data_expanded}/keyring \
  auth get-or-create-key client.admin \
    mon 'allow *' \
    osd 'allow *' \
    mds allow)",
    creates => '/etc/ceph/keyring',
    require => Service["ceph-mon.${name}"],
    onlyif  => "ceph --admin-daemon /var/run/ceph/ceph-mon${name}.asok \
mon_status|egrep -v '\"state\": \"(leader|peon)\"'",
  }

  # FIXME: implement this custom fact
  # it should be a call to
  #   ceph --name mon. --keyring ${mon_data_expanded}/keyring \
  #    auth get-or-create-key client.bootstrap-osd \
  #      mon 'allow command osd create ...; allow command osd crush set ...; \
  #      allow command auth add * osd allow\\ * mon allow\\ rwx; \
  #      allow command mon getmap'
  # ceph_bootstrap_osd_key is a custom fact
  if $::ceph_bootstrap_osd_key {
    @@ceph::key { 'bootstrap-osd':
      secret => $::ceph_bootstrap_osd_key,
    }
  }

  ceph::conf::mon { $name:
    mon_addr => $mon_addr,
    mon_data => $mon_data,
  }

}
