#
# Cookbook Name:: coastlines
# Recipe:: default
#
# Copyright 2014, OpenStreetMap Foundation
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

include_recipe "git"

package %w[
  libsqlite3-dev
  zlib1g-dev
  libbz2-dev
  libexpat1-dev
  libgeos-dev
  libproj-dev
  proj-data
  sqlite3
  libgdal1-dev
  cmake
  make
  g++
  gdal-bin
  spatialite-bin
  cimg-dev
  python-gdal
  bc
  libboost-program-options-dev
  libboost-dev
]

directory = "/srv/coastlines"

directory directory do
  owner "coastline"
  group "coastline"
  mode 0o755
end

git "#{directory}/libosmium" do
  action :sync
  repository "git://github.com/osmcode/libosmium.git"
  revision "v2.14.0"
  user "coastline"
  group "coastline"
end

git "#{directory}/protozero" do
  action :sync
  repository "git://github.com/mapbox/protozero.git"
  revision "v1.6.2"
  user "coastline"
  group "coastline"
end

git "#{directory}/osmcoastline" do
  action :sync
  repository "git://github.com/osmcode/osmcoastline.git"
#  revision "v2.1.4"
  user "coastline"
  group "coastline"
end

git "#{directory}/gdal-tools" do
  action :sync
  repository "https://github.com/imagico/gdal-tools.git"
  revision "db8f634508c6e990b6d9061e83e2df0141854ac0"
  user "coastline"
  group "coastline"
end

git "#{directory}/osmium-tool" do
  action :sync
  repository "git://github.com/osmcode/osmium-tool.git"
  revision "v1.8.0"
  user "coastline"
  group "coastline"
end

git "#{directory}/polysplit" do
  action :sync
  repository "https://github.com/geoloqi/polysplit"
  revision "e0fadaf9ea1eef3faf9d0d1035cc23ca41e1124f"
  user "coastline"
  group "coastline"
end

directory "#{directory}/osmcoastline/build" do
  owner "coastline"
  group "coastline"
  mode "0755"
end

execute "compile-osmcoastline" do
  action :nothing
  command "cmake .. && make && cp src/osmcoastline src/osmcoastline_filter #{directory}/bin/"
  cwd "#{directory}/osmcoastline/build"
  user "coastline"
  group "coastline"
  subscribes :run, "git[#{directory}/protozero]"
  subscribes :run, "git[#{directory}/libosmium]"
  subscribes :run, "git[#{directory}/osmcoastline]"
end

directory "#{directory}/osmium-tool/build" do
  owner "coastline"
  group "coastline"
  mode "0755"
end

execute "compile-osmium-tool" do
  action :nothing
  command "cmake .. && make && cp src/osmium #{directory}/bin/"
  cwd "#{directory}/osmium-tool/build"
  user "coastline"
  group "coastline"
  subscribes :run, "git[#{directory}/protozero]"
  subscribes :run, "git[#{directory}/libosmium]"
  subscribes :run, "git[#{directory}/osmium-tool]"
end


execute "compile-gdal-tools" do
  action :nothing
  command "make gdal_maskcompare_wm && cp gdal_maskcompare_wm #{directory}/bin/"
  cwd "#{directory}/gdal-tools"
  user "coastline"
  group "coastline"
  subscribes :run, "git[#{directory}/gdal-tools]"
end

execute "compile-polysplit" do
  action :nothing
  command "make && cp polysplit #{directory}/bin/"
  cwd "#{directory}/gdal-tools"
  user "coastline"
  group "coastline"
  subscribes :run, "git[#{directory}/polysplit]"
end

%w[planet bin data log pngs].each do |dir|
  directory "#{directory}/#{dir}" do
    owner "coastline"
    group "coastline"
    mode 0o755
  end
end

%w[update-coastlines.sh update-coastline-extracts.sh compare-coastline-polygons.sh update-coastline-shapefiles.sh poly-grid.sh README.odbl].each do |fname|
  template "#{directory}/bin/#{fname}" do
    source "#{fname}.erb"
    owner "coastline"
    group "coastline"
    mode 0o755
    variables :datadir => "#{directory}/data",
              :logdir => "#{directory}/log",
              :planet => "#{directory}/planet/planet.pbf",
              :pngdir => "#{directory}/pngs",
              :sqldir => "#{directory}/osmcoastline/simplify_and_split_spatialite"
  end
end

remote_file "#{directory}/planet/planet.pbf" do
  action :create_if_missing
  source "http://download.geofabrik.de/europe/ireland-and-northern-ireland-latest.osm.pbf"
  owner "coastline"
  group "coastline"
  mode 0o644
end

