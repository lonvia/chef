#
# Cookbook Name:: imagery
# Resource:: imagery_layer
#
# Copyright 2016, OpenStreetMap Foundation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require "yaml"

default_action :create

property :layer, String, :name_property => true
property :site, String, :required => true
property :source, String, :required => true
property :root_layer, [TrueClass, FalseClass], :default => false
property :title, String
property :copyright, String, :default => "Copyright"
property :projection, String, :default => "EPSG:3857"
property :palette, String
property :extent, String
property :background_colour, String
property :resample, String, :default => "average"
property :imagemode, String
property :extension, String, :default => "png"
property :max_zoom, Fixnum, :default => 18
property :url_aliases, [String, Array], :default => []
property :revision, Fixnum, :default => 0
property :overlay, [TrueClass, FalseClass], :default => false
property :default_layer, [TrueClass, FalseClass], :default => false

action :create do
  file "/srv/imagery/layers/#{site}/#{layer}.yml" do
    owner "root"
    group "root"
    mode 0o644
    content YAML.dump(:name => layer,
                      :title => title || layer,
                      :url => "http://{s}.#{site}/layer/#{layer}/{z}/{x}/{y}.png",
                      :attribution => copyright,
                      :default => default_layer,
                      :maxZoom => max_zoom,
                      :overlay => overlay)
  end

  template "/srv/imagery/mapserver/layer-#{layer}.map" do
    cookbook "imagery"
    source "mapserver.map.erb"
    owner "root"
    group "root"
    mode 0o644
    variables new_resource.to_hash
  end

  systemd_service "mapserv-fcgi-#{layer}" do
    description "Map server for #{layer} layer"
    limit_nofile 16384
    environment "MS_MAPFILE" => "/srv/imagery/mapserver/layer-#{layer}.map",
                "MS_MAP_PATTERN" => "^/srv/imagery/mapserver/",
                "MS_DEBUGLEVEL" => "0",
                "MS_ERRORFILE" => "stderr"
    user "imagery"
    group "imagery"
    exec_start_pre "/bin/rm -f /run/mapserver-fastcgi/layer-#{layer}.socket"
    exec_start "/usr/bin/spawn-fcgi -s /run/mapserver-fastcgi/layer-#{layer}.socket -M 0666 -P /run/mapserver-fastcgi/layer-#{layer}.pid -- /usr/bin/multiwatch -f 6 --signal=TERM -- /usr/lib/cgi-bin/mapserv"
    pid_file "/run/mapserver-fastcgi/layer-#{layer}.pid"
    type "forking"
    restart "always"
  end

  service "mapserv-fcgi-#{layer}" do
    provider Chef::Provider::Service::Systemd
    action [:enable, :start]
    supports :status => true, :restart => true, :reload => false
    subscribes :restart, "template[/srv/imagery/mapserver/layer-#{layer}.map]"
    subscribes :restart, "systemd_service[mapserv-fcgi-#{layer}]"
  end

  directory "/srv/imagery/nginx/#{site}" do
    owner "root"
    group "root"
    mode 0o755
    recursive true
  end

  template "/srv/imagery/nginx/#{site}/layer-#{layer}.conf" do
    cookbook "imagery"
    source "nginx_imagery_layer_fragment.conf.erb"
    owner "root"
    group "root"
    mode 0o644
    variables new_resource.to_hash
  end
end

action :delete do
  service "mapserv-fcgi-layer-#{layer}" do
    action [:stop, :disable]
  end

  file "/srv/imagery/mapserver/layer-#{layer}.map" do
    action :delete
  end

  systemd_service "mapserv-fcgi-#{layer}" do
    action :delete
  end

  file "/srv/imagery/nginx/#{site}/layer-#{layer}.conf" do
    action :delete
  end
end

def after_created
  notifies :create, "imagery_site[#{site}]"
  notifies :reload, "service[nginx]"
end
