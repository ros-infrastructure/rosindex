#!/usr/bin/env python3

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

import json
import requests
from pathlib import Path

DEBIAN_URL = 'https://packages.debian.org/stable/allpackages?format=txt.gz'
DEBIAN_JSON_PATH = Path('_data') / 'debian_packages.json'


def main():
    """Download and parse Debian package summaries, with name and description.

       This file should be run periodically to update the debian package descriptions
       Usage: (from the root of the rosindex repo):

       python3 _scripts/debian_descriptions.py
    """
    content = requests.get(DEBIAN_URL).text
    packages = {}
    for line in content.split('\n'):
        # Typical package line:
        # 3270-common (4.1ga10-1.1+b1) Common files for IBM 3270 emulators and pr3287
        left_paren = line.find('(')
        right_paren = line.find(')')
        # The file starts with some beginning material that is not packages.
        if left_paren < 0 or right_paren < 0:
            continue
        # Had issues with ruby crashing while reading unicode characters from the json.
        # Not sure why, but let't just force ascii for now.
        package_name = line[:left_paren - 1].encode('ascii', errors='ignore').decode()
        package_desc = line[right_paren + 2:].encode('ascii', errors='ignore').decode()
        packages[package_name] = package_desc

    if len(packages):
        with DEBIAN_JSON_PATH.open(mode='w') as f:
            json.dump(packages, f)
        print(f'Updated debian description file at {DEBIAN_JSON_PATH} with {len(packages)} packages')
    else:
        print('No packages found')
        exit(1)

if __name__ == '__main__':
    main()
