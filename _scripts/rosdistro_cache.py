#!/usr/bin/env python3

"""Generate a rosdistro CacheConfig file from ROS Index YAML configs and build caches."""

import argparse
import os
import sys

from rosdistro import CacheConfig, get_index_url
from rosdistro.cli.rosdistro_build_cache import main as rosdistro_build_cache_main
import yaml

DEFAULT_CONFIG = ['_config.yml', 'index.yml']
DEFAULT_CACHE_DIR = '_cache'
DEFAULT_CACHE_CONFIG_OUT = '_artifacts/rosdistro_cache_config.yaml'


def load_merged_config(config_arg):
    config = {}
    for file_name in [c.strip() for c in config_arg.split(',') if c.strip()]:
        with open(file_name, 'r', encoding='utf-8') as f:
            file_obj = yaml.safe_load(f) or {}
            config.update(file_obj)
    return config


def get_configured_distros(config):
    raw_distros = (
        list(config.get('ros2_distros') or [])
        + list(config.get('ros_distros') or [])
        + list(config.get('old_ros2_distros') or [])
        + list(config.get('old_ros_distros') or [])
    )
    seen = set()
    distros = []
    for distro in raw_distros:
        if distro and distro not in seen:
            seen.add(distro)
            distros.append(str(distro))
    return distros


def build_cache_config(config):
    raw_max_lines = config.get('max_embedded_content_lines')
    max_lines = (
        int(raw_max_lines)
        if raw_max_lines is not None and int(raw_max_lines) > 0
        else None
    )
    doc_entry = {'enabled': True, 'max_lines': max_lines}

    raw_max_repos = config.get('max_repos')
    limit = (
        int(raw_max_repos)
        if raw_max_repos is not None and int(raw_max_repos) > 0
        else None
    )

    raw_cache_cfg = {
        'release_package_resources': {
            'package.xml': {'enabled': True},
            'README.md': dict(doc_entry),
            'CHANGELOG.rst': dict(doc_entry),
        },
        'source_package_resources': {
            'package.xml': {'enabled': True},
            'README.md': dict(doc_entry),
            'CHANGELOG.rst': dict(doc_entry),
            'launch_files': {'enabled': True},
            'msg_files': {'enabled': True},
            'srv_files': {'enabled': True},
            'action_files': {'enabled': True},
        },
        'source_repo_metadata': {
            'stars': {'enabled': True},
            'description': {'enabled': True},
            'tags': {'enabled': True},
            'last_commit_time': {'enabled': True},
            'contributing': dict(doc_entry),
            'readme': dict(doc_entry),
        },
        'fallback_src_to_doc': True,
        'limit': limit,
    }
    return CacheConfig(raw_cache_cfg)


def write_cache_config(cache_config, output_path):
    abs_output_path = os.path.abspath(output_path)
    os.makedirs(os.path.dirname(abs_output_path), exist_ok=True)
    with open(abs_output_path, 'w', encoding='utf-8') as f:
        yaml.safe_dump(cache_config.to_dict(), f, sort_keys=False)
    return abs_output_path


def _missing_caches(cache_dir, distros):
    missing = []
    for distro in distros:
        candidates = (
            os.path.join(cache_dir, f'{distro}-extended-cache.yaml'),
            os.path.join(cache_dir, f'{distro}-extended-cache.yaml.gz'),
        )
        if not any(os.path.exists(p) for p in candidates):
            missing.append(distro)
    return missing


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description='Generate a rosdistro cache config from ROS Index configs and build caches.'
    )
    parser.add_argument(
        '--config',
        default=','.join(DEFAULT_CONFIG),
        help='Comma-separated list of YAML configuration files (default: _config.yml,index.yml)',
    )
    parser.add_argument(
        '--cache-config-out',
        default=None,
        help=(
            'Path to write generated rosdistro cache config YAML '
            f'(defaults to rosdistro_cache_config in config or {DEFAULT_CACHE_CONFIG_OUT})'
        ),
    )
    parser.add_argument(
        '--cache-dir',
        default=None,
        help=(
            'Directory to store rosdistro cache files '
            f'(defaults to cache_dir in config or {DEFAULT_CACHE_DIR})'
        ),
    )
    parser.add_argument(
        '--index-url',
        default=None,
        help='Override rosdistro index URL (defaults to rosdistro_index_url in config or get_index_url())',
    )
    parser.add_argument(
        '--write-config-only',
        action='store_true',
        default=False,
        help='Only generate the rosdistro cache config file without running rosdistro_build_cache',
    )
    parser.add_argument(
        '--skip-if-present',
        action='store_true',
        default=False,
        help='Skip running rosdistro_build_cache if extended cache files already exist for all configured distros',
    )
    parser.add_argument(
        '--debug',
        action='store_true',
        default=False,
        help='Pass --debug to rosdistro_build_cache',
    )
    parser.add_argument(
        '--preclean',
        action='store_true',
        default=False,
        help='Pass --preclean to rosdistro_build_cache',
    )
    parser.add_argument(
        '--ignore-local',
        action='store_true',
        default=False,
        help='Pass --ignore-local to rosdistro_build_cache',
    )
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    config = load_merged_config(args.config)
    distros = get_configured_distros(config)
    if not distros:
        print('No distributions configured; nothing to cache.')
        return 0

    cache_config = build_cache_config(config)
    index_url = args.index_url or config.get('rosdistro_index_url') or get_index_url()
    cache_dir = args.cache_dir or config.get('cache_dir') or DEFAULT_CACHE_DIR
    cache_config_out = (
        args.cache_config_out
        or config.get('rosdistro_cache_config')
        or DEFAULT_CACHE_CONFIG_OUT
    )

    target_distros = distros
    if args.skip_if_present and not args.write_config_only:
        missing = _missing_caches(cache_dir, distros)
        if not missing:
            print(
                f'Extended cache files already present in {cache_dir} '
                f'for all {len(distros)} configured distros.'
            )
            return 0
        print(f'Building missing extended caches for distros: {", ".join(missing)}')
        target_distros = missing

    abs_config_path = write_cache_config(cache_config, cache_config_out)
    print(
        f'Wrote rosdistro cache config to {abs_config_path} '
        f'(limit={cache_config.limit}, '
        f'max_lines={cache_config.get_source_resource_max_lines("README.md")}, '
        f'distros={distros})'
    )

    if args.write_config_only:
        return 0

    abs_cache_dir = os.path.abspath(cache_dir)
    os.makedirs(abs_cache_dir, exist_ok=True)

    cli_args = ['--config', abs_config_path]
    if args.debug:
        cli_args.append('--debug')
    if args.preclean:
        cli_args.append('--preclean')
    if args.ignore_local:
        cli_args.append('--ignore-local')
    cli_args.append(index_url)
    cli_args.extend(target_distros)

    prev_cwd = os.getcwd()
    try:
        os.chdir(abs_cache_dir)
        rc = rosdistro_build_cache_main(cli_args)
        return rc or 0
    finally:
        os.chdir(prev_cwd)


if __name__ == '__main__':
    sys.exit(main())
