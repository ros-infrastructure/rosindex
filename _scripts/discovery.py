#!/usr/bin/env python3

"""Prepare a JSON file with discovered repos from the rosdistro extended cache."""

import argparse
from collections import defaultdict
import gzip
import json
import os
import sys

from rosdistro import DistributionCache, get_extended_cached_distribution
import yaml

DISCOVERY_RESULTS = '_artifacts/discovery.json'
DISCOVERY_ERRORS = '_artifacts/discovery_errors.json'
DEFAULT_CONFIG = ['_config.yml', 'index.yml']
DEFAULT_CACHE_DIR = '_cache'


class IndexException(Exception):
    def __init__(self, msg, repo_id='UNKNOWN'):
        super().__init__(msg)
        self.msg = msg
        self.repo_id = repo_id
        print(f'ERROR ({self.repo_id}): {self.msg}')

    def to_dict(self):
        return {'msg': self.msg, 'repo_id': self.repo_id}


def _normalize_version(version):
    if version is not None and str(version) != 'HEAD':
        return str(version)
    return 'REMOTE_HEAD'


def _load_distribution_cache(cache_dir, distro):
    candidates = (
        os.path.join(cache_dir, f'{distro}-extended-cache.yaml'),
        os.path.join(cache_dir, f'{distro}-extended-cache.yaml.gz'),
        os.path.join(cache_dir, f'{distro}-cache.yaml'),
        os.path.join(cache_dir, f'{distro}-cache.yaml.gz'),
    )
    for path in candidates:
        if os.path.exists(path):
            if path.endswith('.gz'):
                with gzip.open(path, 'rb') as f:
                    data = yaml.safe_load(f.read().decode('utf-8'))
            else:
                with open(path, 'r', encoding='utf-8') as f:
                    data = yaml.safe_load(f)
            return DistributionCache(distro, data), path
    return None, None


def _get_release_repo_version(release_repo):
    if (
        release_repo.version is not None
        and 'release' in release_repo.tags
        and release_repo.package_names
    ):
        return release_repo.get_release_tag(release_repo.package_names[0])
    return _normalize_version(release_repo.version)


def _get_cached_release_manifest(dist, release_repo):
    release_version = (
        str(release_repo.version).split('-')[0]
        if release_repo.version is not None
        else '0.0.0'
    )
    for pkg_name in release_repo.package_names:
        manifest_xml = dist.get_release_package_xml(pkg_name)
        if manifest_xml is not None:
            return manifest_xml.replace(':{version}', release_version)
    return None


def discover_repos(config, output_path, errors_path, cache_dir=DEFAULT_CACHE_DIR):
    all_distros = list(config.get('distros', [])) + list(config.get('old_distros', []))
    errors = defaultdict(list)
    repos = {}

    for distro in reversed(all_distros):
        repos[distro] = []
        print(f'processing discovery for rosdistro: {distro}')
        cache, cache_path = _load_distribution_cache(cache_dir, distro)
        if cache is None:
            print(f'Could not find cache file for {distro} in {cache_dir}')
            continue

        dist = get_extended_cached_distribution(
            None, distro, cache=cache, allow_lazy_load=False
        )

        for repo_name, repo in dist.repositories.items():
            try:
                source_uri = None
                source_version = None
                source_type = None
                release_manifest_xml = None

                if repo.source_repository is not None:
                    source_uri = str(repo.source_repository.url)
                    source_type = str(repo.source_repository.type)
                    source_version = _normalize_version(repo.source_repository.version)
                elif repo.doc_repository is not None:
                    source_uri = str(repo.doc_repository.url)
                    source_type = str(repo.doc_repository.type)
                    source_version = _normalize_version(repo.doc_repository.version)
                elif repo.release_repository is not None:
                    source_uri = str(repo.release_repository.url)
                    source_type = str(repo.release_repository.type)
                    source_version = _get_release_repo_version(repo.release_repository)
                    release_manifest_xml = _get_cached_release_manifest(
                        dist, repo.release_repository
                    )
                else:
                    raise IndexException(
                        f'No source, doc, or release information for repo: {repo_name} '
                        f'in rosdistro cache: {cache_path}'
                    )

                repos[distro].append({
                    'name': repo_name,
                    'type': source_type,
                    'uri': source_uri,
                    'version': source_version,
                    'release': repo.release_repository is not None,
                    'status': repo.status,
                    'manifest': release_manifest_xml,
                })
            except IndexException as e:
                print(f'repo_name: {repo_name} error: {e}')
                errors[repo_name].append(e.to_dict())

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    os.makedirs(os.path.dirname(os.path.abspath(errors_path)), exist_ok=True)
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(repos, f, indent=2)
    with open(errors_path, 'w', encoding='utf-8') as f:
        json.dump(dict(errors), f, indent=2)
    print('Completed repo discovery')
    return repos, dict(errors)


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description='Discover ROS repos into discovery.json')
    parser.add_argument(
        '--config',
        default=','.join(DEFAULT_CONFIG),
        help='Comma-separated list of YAML configuration files (default: _config.yml,index.yml)',
    )
    parser.add_argument(
        '--path',
        default=DISCOVERY_RESULTS,
        help='Path to save discovery results',
    )
    parser.add_argument(
        '--errors',
        default=DISCOVERY_ERRORS,
        help='Path to save discovery errors',
    )
    parser.add_argument(
        '--cache-dir',
        default=DEFAULT_CACHE_DIR,
        help='Directory containing rosdistro cache files (default: _cache)',
    )
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    config = {}
    for file_name in [c.strip() for c in args.config.split(',') if c.strip()]:
        with open(file_name, 'r', encoding='utf-8') as f:
            file_obj = yaml.safe_load(f) or {}
            config.update(file_obj)

    config['distros'] = (config.get('ros2_distros') or []) + (config.get('ros_distros') or [])
    config['old_distros'] = (config.get('old_ros2_distros') or []) + (
        config.get('old_ros_distros') or []
    )
    discover_repos(config, args.path, args.errors, cache_dir=args.cache_dir)


if __name__ == '__main__':
    sys.exit(main())
