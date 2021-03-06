#
# Cookbook Name:: hardware
# Recipe:: default
#
# Copyright 2012, OpenStreetMap Foundation
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
#

include_recipe "tools"
include_recipe "munin"

ohai_plugin "hardware" do
  template "ohai.rb.erb"
end

case node[:cpu][:"0"][:vendor_id]
when "GenuineIntel"
  package "intel-microcode"
end

case node[:cpu][:"0"][:vendor_id]
when "AuthenticAMD"
  if node[:lsb][:release].to_f >= 14.04
    package "amd64-microcode"
  end
end

if node[:dmi] && node[:dmi][:system]
  case node[:dmi][:system][:manufacturer]
  when "empty"
    manufacturer = node[:dmi][:base_board][:manufacturer]
    product = node[:dmi][:base_board][:product_name]
  else
    manufacturer = node[:dmi][:system][:manufacturer]
    product = node[:dmi][:system][:product_name]
  end
else
  manufacturer = "Unknown"
  product = "Unknown"
end

units = []

if node[:roles].include?("bytemark") || node[:roles].include?("exonetric")
  units << "0"
end

case manufacturer
when "HP"
  package "hponcfg"
  package "hp-health"
  units << "1"
when "TYAN"
  units << "0"
when "TYAN Computer Corporation"
  units << "0"
when "Supermicro"
  case product
  when "H8DGU", "X9SCD", "X7DBU", "X7DW3", "X9DR7/E-(J)LN4F", "X9DR3-F", "X9DRW", "SYS-2028U-TN24R4T+"
    units << "1"
  else
    units << "0"
  end
when "IBM"
  units << "0"
end

units.sort.uniq.each do |unit|
  if node[:lsb][:release].to_f >= 16.04
    service "serial-getty@ttyS#{unit}" do
      action [:enable, :start]
    end
  else
    file "/etc/init/ttySttyS#{unit}.conf" do
      action :delete
    end

    template "/etc/init/ttyS#{unit}.conf" do
      source "tty.conf.erb"
      owner "root"
      group "root"
      mode 0o644
      variables :unit => unit
    end

    service "ttyS#{unit}" do
      provider Chef::Provider::Service::Upstart
      action [:enable, :start]
      supports :status => true, :restart => true, :reload => false
      subscribes :restart, "template[/etc/init/ttyS#{unit}.conf]"
    end
  end
end

# if we need a different / special kernel version to make the hardware
# work (e.g: https://github.com/openstreetmap/operations/issues/45) then
# ensure that we have the package installed. the grub template will
# make sure that this is the default on boot.
if node[:hardware][:grub][:kernel]
  kernel_version = node[:hardware][:grub][:kernel]

  package "linux-image-#{kernel_version}-generic"
  package "linux-image-extra-#{kernel_version}-generic"
  package "linux-headers-#{kernel_version}-generic"

  boot_device = IO.popen(["df", "/boot"]).readlines.last.split.first
  boot_uuid = IO.popen(["blkid", "-o", "value", "-s", "UUID", boot_device]).readlines.first.chomp
  grub_entry = "gnulinux-advanced-#{boot_uuid}>gnulinux-#{kernel_version}-advanced-#{boot_uuid}"
else
  grub_entry = "0"
end

if File.exist?("/etc/default/grub")
  execute "update-grub" do
    action :nothing
    command "/usr/sbin/update-grub"
  end

  template "/etc/default/grub" do
    source "grub.erb"
    owner "root"
    group "root"
    mode 0o644
    variables :units => units, :entry => grub_entry
    notifies :run, "execute[update-grub]"
  end
end

execute "update-initramfs" do
  action :nothing
  command "update-initramfs -u -k all"
  user "root"
  group "root"
end

template "/etc/initramfs-tools/conf.d/mdadm" do
  source "initramfs-mdadm.erb"
  owner "root"
  group "root"
  mode 0o644
  notifies :run, "execute[update-initramfs]"
end

package "haveged"
service "haveged" do
  action [:enable, :start]
end

if node[:kernel][:modules].include?("ipmi_si")
  package "ipmitool"
end

if node[:lsb][:release].to_f >= 12.10
  package "irqbalance"

  template "/etc/default/irqbalance" do
    source "irqbalance.erb"
    owner "root"
    group "root"
    mode 0o644
  end

  service "irqbalance" do
    action [:start, :enable]
    supports :status => false, :restart => true, :reload => false
    subscribes :restart, "template[/etc/default/irqbalance]"
  end
end

tools_packages = []
status_packages = {}

node[:kernel][:modules].each_key do |modname|
  case modname
  when "cciss"
    tools_packages << "hpssacli"
    status_packages["cciss-vol-status"] ||= []
  when "hpsa"
    tools_packages << "hpssacli"
    status_packages["cciss-vol-status"] ||= []
  when "mptsas"
    tools_packages << "lsiutil"
    # status_packages["mpt-status"] ||= []
  when "mpt2sas", "mpt3sas"
    tools_packages << "sas2ircu"
    status_packages["sas2ircu-status"] ||= []
  when "megaraid_mm"
    tools_packages << "megactl"
    status_packages["megaraid-status"] ||= []
  when "megaraid_sas"
    tools_packages << "megacli"
    status_packages["megaclisas-status"] ||= []
  when "aacraid"
    tools_packages << "arcconf"
    status_packages["aacraid-status"] ||= []
  when "arcmsr"
    tools_packages << "areca"
  end
end

node[:block_device].each do |name, attributes|
  next unless attributes[:vendor] == "HP" && attributes[:model] == "LOGICAL VOLUME"

  if name =~ /^cciss!(c[0-9]+)d[0-9]+$/
    status_packages["cciss-vol-status"] |= ["cciss/#{Regexp.last_match[1]}d0"]
  else
    Dir.glob("/sys/block/#{name}/device/scsi_generic/*").each do |sg|
      status_packages["cciss-vol-status"] |= [File.basename(sg)]
    end
  end
end

%w(hpssacli lsiutil sas2ircu megactl megacli arcconf).each do |tools_package|
  if tools_packages.include?(tools_package)
    package tools_package
  else
    package tools_package do
      action :purge
    end
  end
end

if tools_packages.include?("areca")
  include_recipe "git"

  git "/opt/areca" do
    action :sync
    repository "git://chef.openstreetmap.org/areca.git"
    user "root"
    group "root"
  end
else
  directory "/opt/areca" do
    action :delete
    recursive true
  end
end

["cciss-vol-status", "mpt-status", "sas2ircu-status", "megaraid-status", "megaclisas-status", "aacraid-status"].each do |status_package|
  if status_packages.include?(status_package)
    package status_package

    template "/etc/default/#{status_package}d" do
      source "raid.default.erb"
      owner "root"
      group "root"
      mode 0o644
      variables :devices => status_packages[status_package]
    end

    service "#{status_package}d" do
      action [:start, :enable]
      supports :status => false, :restart => true, :reload => false
      subscribes :restart, "template[/etc/default/#{status_package}d]"
    end
  else
    package status_package do
      action :purge
    end

    file "/etc/default/#{status_package}d" do
      action :delete
    end
  end
end

disks = if node[:hardware][:disk]
          node[:hardware][:disk][:disks]
        else
          []
        end

intel_ssds = disks.select { |d| d[:vendor] == "INTEL" && d[:model] =~ /^SSD/ }

nvmes = if node[:hardware][:pci]
          node[:hardware][:pci].values.select { |pci| pci[:driver] == "nvme" }
        else
          []
        end

intel_nvmes = nvmes.select { |pci| pci[:vendor_name] == "Intel Corporation" }

if !intel_ssds.empty? || !intel_nvmes.empty?
  package "unzip"
  package "alien"

  remote_file "#{Chef::Config[:file_cache_path]}/DataCenterTool_3_0_0_Linux.zip" do
    source "https://downloadmirror.intel.com/23931/eng/DataCenterTool_3_0_0_Linux.zip"
  end

  execute "unzip-DataCenterTool" do
    command "unzip DataCenterTool_3_0_0_Linux.zip isdct-3.0.0.400-15.x86_64.rpm"
    cwd Chef::Config[:file_cache_path]
    user "root"
    group "root"
    not_if { File.exist?("#{Chef::Config[:file_cache_path]}/isdct-3.0.0.400-15.x86_64.rpm") }
  end

  execute "alien-isdct" do
    command "alien --to-deb isdct-3.0.0.400-15.x86_64.rpm"
    cwd Chef::Config[:file_cache_path]
    user "root"
    group "root"
    not_if { File.exist?("#{Chef::Config[:file_cache_path]}/isdct_3.0.0.400-16_amd64.deb") }
  end

  dpkg_package "isdct" do
    source "#{Chef::Config[:file_cache_path]}/isdct_3.0.0.400-16_amd64.deb"
  end
end

disks = disks.map do |disk|
  next if disk[:state] == "spun_down"

  if disk[:smart_device]
    controller = node[:hardware][:disk][:controllers][disk[:controller]]
    device = controller[:device].sub("/dev/", "")
    smart = disk[:smart_device]

    if device.start_with?("cciss/") && smart =~ /^cciss,(\d+)$/
      array = node[:hardware][:disk][:arrays][disk[:arrays].first]
      munin = "cciss-3#{array[:wwn]}-#{Regexp.last_match(1)}"
    elsif smart =~ /^.*,(\d+)$/
      munin = "#{device}-#{Regexp.last_match(1)}"
    elsif smart =~ %r{^.*,(\d+)/(\d+)$}
      munin = "#{device}-#{Regexp.last_match(1)}:#{Regexp.last_match(2)}"
    end
  elsif disk[:device]
    device = disk[:device].sub("/dev/", "")
    munin = device
  end

  next if device.nil?

  Hash[
    :device => device,
    :smart => smart,
    :munin => munin,
    :hddtemp => munin.tr("-:", "_")
  ]
end

disks = disks.compact

if disks.count > 0
  package "smartmontools"

  template "/usr/local/bin/smartd-mailer" do
    source "smartd-mailer.erb"
    owner "root"
    group "root"
    mode 0o755
  end

  template "/etc/smartd.conf" do
    source "smartd.conf.erb"
    owner "root"
    group "root"
    mode 0o644
    variables :disks => disks
    notifies :reload, "service[smartmontools]"
  end

  template "/etc/default/smartmontools" do
    source "smartmontools.erb"
    owner "root"
    group "root"
    mode 0o644
    notifies :restart, "service[smartmontools]"
  end

  service "smartmontools" do
    action [:enable, :start]
    supports :status => true, :restart => true, :reload => true
  end

  # Don't try and do munin monitoring of disks behind
  # an Areca controller as they only allow one thing to
  # talk to the controller at a time and smartd will
  # throw errors if it clashes with munin
  disks = disks.reject { |disk| disk[:smart] && disk[:smart].start_with?("areca,") }

  disks.each do |disk|
    munin_plugin "smart_#{disk[:munin]}" do
      target "smart_"
      conf "munin.smart.erb"
      conf_variables :disk => disk
    end
  end
else
  service "smartmontools" do
    action [:stop, :disable]
  end
end

if disks.count > 0
  munin_plugin "hddtemp_smartctl" do
    conf "munin.hddtemp.erb"
    conf_variables :disks => disks
  end
else
  munin_plugin "hddtemp_smartctl" do
    action :delete
    conf "munin.hddtemp.erb"
  end
end

plugins = Dir.glob("/etc/munin/plugins/smart_*").map { |p| File.basename(p) } -
          disks.map { |d| "smart_#{d[:munin]}" }

plugins.each do |plugin|
  munin_plugin plugin do
    action :delete
  end
end

if File.exist?("/etc/mdadm/mdadm.conf")
  mdadm_conf = edit_file "/etc/mdadm/mdadm.conf" do |line|
    line.gsub!(/^MAILADDR .*$/, "MAILADDR admins@openstreetmap.org")

    line
  end

  file "/etc/mdadm/mdadm.conf" do
    owner "root"
    group "root"
    mode 0o644
    content mdadm_conf
  end

  service "mdadm" do
    action :nothing
    subscribes :restart, "file[/etc/mdadm/mdadm.conf]"
  end
end

template "/etc/modules" do
  source "modules.erb"
  owner "root"
  group "root"
  mode 0o644
end

if node[:lsb][:release].to_f <= 12.10
  service "module-init-tools" do
    provider Chef::Provider::Service::Upstart
    action :nothing
    subscribes :start, "template[/etc/modules]"
  end
else
  service "kmod" do
    if node[:lsb][:release].to_f >= 15.10
      provider Chef::Provider::Service::Systemd
    else
      provider Chef::Provider::Service::Upstart
    end
    action :nothing
    subscribes :start, "template[/etc/modules]"
  end
end

if node[:hardware][:watchdog]
  package "watchdog"

  template "/etc/default/watchdog" do
    source "watchdog.erb"
    owner "root"
    group "root"
    mode 0o644
    variables :module => node[:hardware][:watchdog]
  end

  service "watchdog" do
    action [:enable, :start]
  end
end

unless Dir.glob("/sys/class/hwmon/hwmon*").empty?
  package "lm-sensors"

  Dir.glob("/sys/devices/platform/coretemp.*").each do |coretemp|
    cpu = File.basename(coretemp).sub("coretemp.", "").to_i
    chip = format("coretemp-isa-%04d", cpu)

    temps = if File.exist?("#{coretemp}/name")
              Dir.glob("#{coretemp}/temp*_input").map do |temp|
                File.basename(temp).sub("temp", "").sub("_input", "").to_i
              end.sort
            else
              Dir.glob("#{coretemp}/hwmon/hwmon*/temp*_input").map do |temp|
                File.basename(temp).sub("temp", "").sub("_input", "").to_i
              end.sort
            end

    if temps.first == 1
      node.default[:hardware][:sensors][chip][:temps][:temp1][:label] = "CPU #{cpu}"
      temps.shift
    end

    temps.each_with_index do |temp, index|
      node.default[:hardware][:sensors][chip][:temps]["temp#{temp}"][:label] = "CPU #{cpu} Core #{index}"
    end
  end

  execute "/etc/sensors.d/chef.conf" do
    action :nothing
    command "/usr/bin/sensors -s"
    user "root"
    group "root"
  end

  template "/etc/sensors.d/chef.conf" do
    source "sensors.conf.erb"
    owner "root"
    group "root"
    mode 0o644
    notifies :run, "execute[/etc/sensors.d/chef.conf]"
  end
end
