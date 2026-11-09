#!/usr/bin/env python3

# Copyright 2025 R. Kent James <kent@caspia.com>
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

import argparse
import json
from pathlib import Path
import sys
import time
import requests
import yaml

ROS_PYTHON_DEPS_URL = 'https://github.com/ros/rosdistro/raw/refs/heads/master/rosdep/python.yaml'
PYPI_API_URL = 'https://pypi.org/pypi/{package_name}/json'
DEFAULT_OUTDIR = '_artifacts'
DEFAULT_PIP_FILE = 'pip_packages.json'
DEFAULT_MAX_AGE_HOURS = 20.0

'''
This package locates required pip descriptions from file rosdeps/python.yaml in
ROS's rosdistro. It then uses an API from pypi.org to locate a description for that
dependency.

These descriptions are stored in a file 'pip_packages.json' (typically in the _artifacts directory)
that is a JSON file containing a single dictionary, like:

{
 "adafruit-ads1x15-pip": "Python code to use the ADS1015 and ADS1115 analog to digital converters with a Raspberry Pi or BeagleBone black.",
 "adafruit-gpio-pip": "Library to provide a cross-platform GPIO interface on the Raspberry Pi and Beaglebone Black using the RPi.GPIO and Adafruit_BBIO libraries.",
...
}

The keys for the dictionary are strings that refer to the ROS dependency name from rosdistro.
The values for the dictionary are strings containing the description of the dependency obtained from pypi.org

Typical rosdep/python.yaml entries from rosdistro's python.yaml:

carla-pip:
  debian:
    pip:
      packages: [carla]

or

python3-dm-env-pip:
  '*':
    pip:
      packages: [dm-env]

or

quadprog-pip:
  debian:
    pip: [quadprog]

or

python-grpc-tools:
  debian:
    '*': [python-grpc-tools]
    stretch:
      pip: [grpcio-tools]
  nixos: [pythonPackages.grpcio-tools]
  ubuntu:
    '*': [python-grpc-tools]
    bionic:
      pip: [grpcio-tools]

      or

python-gpiozero:
  debian:
    buster: [python-gpiozero]
  ubuntu:
    bionic: [python-gpiozero]

'''

def find_pip_name(item):
    if type(item) is dict:
        if 'pip' in item:
            if type(item['pip']) is list and len(item['pip']):
                return item['pip'][0]
            if 'packages' in item['pip'] and len(item['pip']['packages']):
                return item['pip']['packages'][0]
        for entry in item.values():
            result = find_pip_name(entry)
            if result:
                return result
    return None

def guess_pip_name(item):
    if type(item) is str:
        if item.startswith('python-'):
            return item[7:]
        if item.startswith('python3-'):
            return item[8:]
    if type(item) is list and len(item):
        return guess_pip_name(item[0])
    if type(item) is dict:
        for key, value in item.items():
            if key in ['debian', 'ubuntu']:
                result = guess_pip_name(value)
                if result:
                    return result
    return None


def get_pip_names(outdir: Path):
    # Examines rosdep to get pip package names of ros dependencies.
    pip_package_names = {}
    response = requests.get(ROS_PYTHON_DEPS_URL, allow_redirects=True)
    content = response.content.decode('utf-8')
    rosdeps = yaml.safe_load(content)
    found_count = 0
    guessed_count = 0

    for key, value in rosdeps.items():
        name = find_pip_name(value)
        if name:
            pip_package_names[key] = name
            found_count += 1
        else:
            name = guess_pip_name(value)
            if name:
                pip_package_names[key] = name
                guessed_count += 1
    print(f'pip names found {found_count}, guessed {guessed_count}')

    with open(outdir / 'pip_package_names.json', 'w', encoding ='utf8') as json_file:
        json.dump(pip_package_names, json_file, ensure_ascii=True, indent=1)

    return pip_package_names


def get_cache_age_hours(filepath: Path, now: float = None):
    """Return the age in hours of a valid non-empty JSON dict file, or None if missing/invalid."""
    if not filepath.is_file():
        return None
    try:
        stat_result = filepath.stat()
        if stat_result.st_size == 0:
            return None
        with open(filepath, 'r', encoding='utf-8') as json_file:
            data = json.load(json_file)
        if not isinstance(data, dict) or not data:
            return None
    except (OSError, json.JSONDecodeError):
        return None

    current_time = time.time() if now is None else now
    return max(0.0, (current_time - stat_result.st_mtime) / 3600.0)


def save_pip_descriptions(
    outdir: str = None,
    output_file: str = None,
    max_age_hours: float = DEFAULT_MAX_AGE_HOURS,
    force: bool = False,
    now: float = None,
):
    # Get descriptions of pip packages in rosdep, store as json file to outdir.
    if outdir is not None:
        outPath = Path(outdir)
    elif output_file is not None:
        outPath = Path(output_file).parent
    else:
        outPath = Path(DEFAULT_OUTDIR)

    output_path = Path(output_file) if output_file is not None else (outPath / DEFAULT_PIP_FILE)

    if not force and max_age_hours is not None and max_age_hours > 0:
        age_hours = get_cache_age_hours(output_path, now=now)
        if age_hours is not None:
            if age_hours <= max_age_hours:
                print(
                    f'Pip descriptions file {output_path} is {age_hours:.2f} hours old '
                    f'(<= {max_age_hours:g} hours); skipping recrawl.'
                )
                return False
            print(
                f'Pip descriptions file {output_path} is {age_hours:.2f} hours old '
                f'(> {max_age_hours:g} hours); triggering recrawl.'
            )

    outPath.mkdir(parents=True, exist_ok=True)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    pip_package_names = get_pip_names(outPath)
    pip_descriptions = {}
    for key, value in pip_package_names.items():
        summary = None
        url = PYPI_API_URL.format(package_name=value)
        try:
            # requests.get redirects missing pages to the error page, obscuring missing packages.
            response = requests.get(url, allow_redirects=False)
            if response.status_code == requests.codes.ok:
                result = response.json()
                if 'info' in result:
                    summary = result['info'].get('summary')
        except RuntimeError as e:
            print(f'save_pip_descriptions error for package {value}: {e}')

        if summary:
            pip_descriptions[key] = summary
        else:
            print(f'No pip summary found for {key}: {value}')

    if pip_descriptions:
        with open(output_path, 'w', encoding ='utf8') as json_file:
            json.dump(pip_descriptions, json_file, ensure_ascii=True, indent=1)
        return True
    else:
        print('Failed to save pip descriptions file, no descriptions found.')
        return False


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description='Crawl PyPI for ROS pip dependency descriptions.'
    )
    parser.add_argument(
        '--outdir',
        default=None,
        help=f'Directory to store output files (default: {DEFAULT_OUTDIR})',
    )
    parser.add_argument(
        '--output',
        default=None,
        help=f'Path to save pip descriptions JSON (default: <outdir>/{DEFAULT_PIP_FILE})',
    )
    parser.add_argument(
        '--max-age-hours',
        type=float,
        default=DEFAULT_MAX_AGE_HOURS,
        help=(
            'Only trigger a recrawl if existing descriptions file is more than '
            f'this many hours old (default: {DEFAULT_MAX_AGE_HOURS:g}; <= 0 always recrawls)'
        ),
    )
    parser.add_argument(
        '--force',
        action='store_true',
        default=False,
        help='Force a recrawl regardless of existing file age',
    )
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    save_pip_descriptions(
        outdir=args.outdir,
        output_file=args.output,
        max_age_hours=args.max_age_hours,
        force=args.force,
    )
    return 0


if __name__ == '__main__':
    sys.exit(main())
