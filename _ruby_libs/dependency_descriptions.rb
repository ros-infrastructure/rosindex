# Copyright 2024 R. Kent James
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'json'
require 'net/http'
require 'uri'

PIP_FILE = '_artifacts/pip_packages.json'
DEBIAN_FILE = '_artifacts/debian_packages.json'


def get_debian_descriptions()
    # Get debian descriptions from a file.
    # Returned descriptions are indexed by debian package name.
    if File.exist?(DEBIAN_FILE)
        puts 'Reading debian descriptions from saved file'.green
        debian_descriptions_json = File.read(DEBIAN_FILE)
        return JSON.parse(debian_descriptions_json)
    else
        puts 'Debian descriptions file does not exist, continuing with no debian descriptions'.red
        return {}
    end
end


def get_pip_descriptions()
    # Get pip dependency descriptions from a file.
    # Returned hash is indexed using rosdep dependency name.

    if File.exist?(PIP_FILE)
        puts 'Reading pip descriptions from saved file'.green
        pip_descriptions_json = File.read(PIP_FILE)
        return JSON.parse(pip_descriptions_json)
    else
        puts 'PIP descriptions file does not exist, continuing with no pip descriptions'.red
        return {}
    end
end
