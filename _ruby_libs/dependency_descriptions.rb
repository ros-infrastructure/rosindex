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

require 'net/http'
require 'uri'

DEBIAN_URL = 'https://packages.debian.org/stable/allpackages?format=txt.gz'

def get_debian_descriptions()
    content_unicode = Net::HTTP.get(URI(DEBIAN_URL))
    # The package file seems to have unicode that confuses ruby. Just force to ascii.
    content = content_unicode.encode("US-ASCII", invalid: :replace, undef: :replace)
    packages = {}
    content.lines.each do |line|
        # Typical package line:
        # 3270-common (4.1ga10-1.1+b1) Common files for IBM 3270 emulators and pr3287
        left_paren = line.index('(')
        right_paren = line.index(')')
        # The file starts with some beginning material that is not packages.
        if not left_paren or not right_paren then next end
        package_name = line[0..left_paren - 2]
        package_desc = line[right_paren + 2..line.length - 1]
        packages[package_name] = package_desc
    end
    packages
end
