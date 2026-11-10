#!/usr/bin/env python3

"""Prepare a JSON file with discovered repos and package resources from the rosdistro extended cache."""

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

README_CANDIDATES = ('README.md', 'README.rst', 'README.txt', 'README')
CHANGELOG_CANDIDATES = ('CHANGELOG.rst', 'CHANGELOG.md', 'CHANGELOG.txt', 'CHANGELOG')
CONTRIBUTING_CANDIDATES = (
    'CONTRIBUTING.md',
    'CONTRIBUTING.rst',
    'CONTRIBUTING.txt',
    'CONTRIBUTING',
)


class IndexException(Exception):
    def __init__(self, msg, repo_id='UNKNOWN'):
        super().__init__(msg)
        self.msg = msg
        self.repo_id = repo_id
        print(f'ERROR ({self.repo_id}): {self.msg}')

    def to_dict(self):
        return {'msg': self.msg, 'repo_id': self.repo_id}


def _resolve_version(version, repo_cache=None):
    if version is not None and str(version) not in ('HEAD', 'REMOTE_HEAD'):
        return str(version)
    if repo_cache is not None and repo_cache.ref():
        return str(repo_cache.ref())
    return 'HEAD'


def _format_commit_date(raw_date):
    if not raw_date:
        return None
    date_str = str(raw_date).strip()
    if len(date_str) >= 10:
        return date_str[:10]
    return date_str


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


def _get_release_repo_version(release_repo, repo_cache=None):
    if (
        release_repo.version is not None
        and 'release' in release_repo.tags
        and release_repo.package_names
    ):
        return release_repo.get_release_tag(release_repo.package_names[0])
    return _resolve_version(release_repo.version, repo_cache=repo_cache)


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


def _is_valid_doc(content):
    return isinstance(content, str) and bool(content) and content != 'Missing'


def _looks_like_rst(content):
    if not isinstance(content, str):
        return False
    return (
        content.startswith('.. ')
        or '\n.. ' in content
        or '`_' in content
        or '::\n' in content
    )


def _extract_doc_from_mapping(mapping, candidates, fallback_key=None):
    if not isinstance(mapping, dict):
        return None, None
    for filename in candidates:
        content = mapping.get(filename)
        if _is_valid_doc(content):
            return content, filename
    if fallback_key:
        val = mapping.get(fallback_key)
        if isinstance(val, dict):
            content = val.get('content')
            filename = val.get('filename') or candidates[0]
            if _is_valid_doc(content):
                return content, filename
        elif _is_valid_doc(val):
            filename = candidates[1] if len(candidates) > 1 and _looks_like_rst(val) else candidates[0]
            return val, filename
    return None, None


def _extract_doc_from_repo_metadata(repo_cache, meta_key, candidates, root_pkg_data=None):
    if repo_cache is None:
        return None, None
    val = repo_cache.get_metadata(meta_key)
    if isinstance(val, dict):
        content = val.get('content')
        filename = val.get('filename') or repo_cache.get_metadata(f'{meta_key}_filename') or candidates[0]
        if _is_valid_doc(content):
            return content, filename
    elif _is_valid_doc(val):
        filename = repo_cache.get_metadata(f'{meta_key}_filename')
        if not filename:
            if meta_key == 'readme' and isinstance(root_pkg_data, dict):
                if _is_valid_doc(root_pkg_data.get('README.md')):
                    filename = candidates[0]
                else:
                    filename = candidates[1] if len(candidates) > 1 else candidates[0]
            elif _looks_like_rst(val):
                filename = candidates[1] if len(candidates) > 1 else candidates[0]
            else:
                filename = candidates[0]
        return val, filename
    for filename in candidates:
        content = repo_cache.get_metadata(filename)
        if _is_valid_doc(content):
            return content, filename
    return None, None


def _extract_package_entry(pkg_name, pkg_data, rel_res=None, release_version=None):
    rel_res = rel_res if isinstance(rel_res, dict) else {}
    pkg_data = pkg_data if isinstance(pkg_data, dict) else {}

    package_xml = pkg_data.get('package.xml') or rel_res.get('package.xml')
    if not package_xml:
        return None
    if release_version and ':{version}' in package_xml:
        package_xml = package_xml.replace(':{version}', release_version)

    package_path = pkg_data.get('package_path', '')
    if package_path is None:
        package_path = ''

    readme, readme_filename = _extract_doc_from_mapping(
        pkg_data, README_CANDIDATES, fallback_key='readme'
    )
    if readme is None:
        readme, readme_filename = _extract_doc_from_mapping(
            rel_res, README_CANDIDATES, fallback_key='readme'
        )

    changelog, changelog_filename = _extract_doc_from_mapping(
        pkg_data, CHANGELOG_CANDIDATES, fallback_key='changelog'
    )
    if changelog is None:
        changelog, changelog_filename = _extract_doc_from_mapping(
            rel_res, CHANGELOG_CANDIDATES, fallback_key='changelog'
        )

    launch_files = pkg_data.get('launch_files')
    if launch_files is None:
        launch_files = rel_res.get('launch_files') or []

    msg_files = pkg_data.get('msg_files')
    if msg_files is None:
        msg_files = rel_res.get('msg_files') or []

    srv_files = pkg_data.get('srv_files')
    if srv_files is None:
        srv_files = rel_res.get('srv_files') or []

    action_files = pkg_data.get('action_files')
    if action_files is None:
        action_files = rel_res.get('action_files') or []

    extra_readmes = pkg_data.get('readmes') or rel_res.get('readmes')

    entry = {
        'name': pkg_name,
        'package_path': package_path,
        'package.xml': package_xml,
        'readme': readme,
        'readme_filename': readme_filename,
        'changelog': changelog,
        'changelog_filename': changelog_filename,
        'launch_files': launch_files,
        'msg_files': msg_files,
        'srv_files': srv_files,
        'action_files': action_files,
    }
    if extra_readmes:
        entry['readmes'] = extra_readmes
    return entry


def _extract_repo_packages_and_docs(cache, dist, repo_name, repo):
    repo_cache = cache.source_repo_resources.get(repo_name) or dist.get_source_repo_resources(repo_name)
    release_repo = repo.release_repository
    release_version = (
        str(release_repo.version).split('-')[0]
        if release_repo is not None and release_repo.version is not None
        else '0.0.0'
    )

    packages = {}
    root_pkg_data = None

    if repo_cache is not None:
        for pkg_name in sorted(repo_cache.keys()):
            pkg_data = repo_cache[pkg_name]
            if isinstance(pkg_data, dict) and pkg_data.get('package_path', '') in ('', '.'):
                root_pkg_data = pkg_data
            rel_res = cache.release_resources.get(pkg_name)
            entry = _extract_package_entry(
                pkg_name, pkg_data, rel_res=rel_res, release_version=release_version
            )
            if entry is not None:
                packages[pkg_name] = entry

    if not packages and release_repo is not None:
        pkg_names = release_repo.package_names or []
        for pkg_name in sorted(pkg_names):
            rel_res = cache.release_resources.get(pkg_name)
            if not isinstance(rel_res, dict):
                continue
            default_path = '' if len(pkg_names) == 1 else pkg_name
            entry = _extract_package_entry(
                pkg_name,
                {'package_path': default_path},
                rel_res=rel_res,
                release_version=release_version,
            )
            if entry is not None:
                packages[pkg_name] = entry

    repo_readme, repo_readme_filename = _extract_doc_from_repo_metadata(
        repo_cache, 'readme', README_CANDIDATES, root_pkg_data=root_pkg_data
    )
    if repo_readme is None and root_pkg_data is not None:
        repo_readme, repo_readme_filename = _extract_doc_from_mapping(
            root_pkg_data, README_CANDIDATES, fallback_key='readme'
        )
    if repo_readme is None and len(packages) == 1:
        sole_pkg = next(iter(packages.values()))
        if sole_pkg.get('package_path', '') in ('', '.') and sole_pkg.get('readme'):
            repo_readme = sole_pkg['readme']
            repo_readme_filename = sole_pkg.get('readme_filename') or 'README.md'

    if repo_readme is not None:
        for pkg_entry in packages.values():
            if pkg_entry.get('package_path', '') in ('', '.') and not pkg_entry.get('readme'):
                pkg_entry['readme'] = repo_readme
                pkg_entry['readme_filename'] = repo_readme_filename or 'README.md'

    repo_contributing, repo_contributing_filename = _extract_doc_from_repo_metadata(
        repo_cache, 'contributing', CONTRIBUTING_CANDIDATES, root_pkg_data=root_pkg_data
    )
    if repo_contributing is None and root_pkg_data is not None:
        repo_contributing, repo_contributing_filename = _extract_doc_from_mapping(
            root_pkg_data, CONTRIBUTING_CANDIDATES, fallback_key='contributing'
        )

    last_commit_time = None
    stars = None
    description = None
    tags = None
    ignored = False

    if repo_cache is not None:
        raw_commit_time = (
            repo_cache.last_commit_time()
            or repo_cache.get_metadata('pushed_at')
            or repo_cache.get_metadata('last_update_time')
        )
        last_commit_time = _format_commit_date(raw_commit_time)
        stars = repo_cache.stars()
        description = repo_cache.description()
        tags = repo_cache.tags()
        ignored = bool(
            repo_cache.get_metadata('ignored')
            or repo_cache.get_metadata('rosindex_ignore')
        )

    return {
        'repo_cache': repo_cache,
        'packages': packages,
        'last_commit_time': last_commit_time,
        'readme': repo_readme,
        'readme_filename': repo_readme_filename,
        'contributing': repo_contributing,
        'contributing_filename': repo_contributing_filename,
        'stars': stars,
        'description': description,
        'tags': tags,
        'ignored': ignored,
    }


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
                extracted = _extract_repo_packages_and_docs(cache, dist, repo_name, repo)
                repo_cache = extracted['repo_cache']

                source_uri = None
                source_version = None
                source_type = None
                release_manifest_xml = None

                if repo.source_repository is not None:
                    source_uri = str(repo.source_repository.url)
                    source_type = str(repo.source_repository.type)
                    source_version = _resolve_version(
                        repo.source_repository.version, repo_cache=repo_cache
                    )
                elif repo.doc_repository is not None:
                    source_uri = str(repo.doc_repository.url)
                    source_type = str(repo.doc_repository.type)
                    source_version = _resolve_version(
                        repo.doc_repository.version, repo_cache=repo_cache
                    )
                elif repo.release_repository is not None:
                    source_uri = str(repo.release_repository.url)
                    source_type = str(repo.release_repository.type)
                    source_version = _get_release_repo_version(
                        repo.release_repository, repo_cache=repo_cache
                    )
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
                    'last_commit_time': extracted['last_commit_time'],
                    'readme': extracted['readme'],
                    'readme_filename': extracted['readme_filename'],
                    'contributing': extracted['contributing'],
                    'contributing_filename': extracted['contributing_filename'],
                    'stars': extracted['stars'],
                    'description': extracted['description'],
                    'tags': extracted['tags'],
                    'ignored': extracted['ignored'],
                    'packages': extracted['packages'],
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
        default=None,
        help=(
            'Path to save discovery results '
            f'(defaults to discovery_results in config or {DISCOVERY_RESULTS})'
        ),
    )
    parser.add_argument(
        '--errors',
        default=None,
        help=(
            'Path to save discovery errors '
            f'(defaults to discovery_errors in config or {DISCOVERY_ERRORS})'
        ),
    )
    parser.add_argument(
        '--cache-dir',
        default=None,
        help=(
            'Directory containing rosdistro cache files '
            f'(defaults to cache_dir in config or {DEFAULT_CACHE_DIR})'
        ),
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
    output_path = args.path or config.get('discovery_results') or DISCOVERY_RESULTS
    errors_path = args.errors or config.get('discovery_errors') or DISCOVERY_ERRORS
    cache_dir = args.cache_dir or config.get('cache_dir') or DEFAULT_CACHE_DIR
    discover_repos(config, output_path, errors_path, cache_dir=cache_dir)


if __name__ == '__main__':
    sys.exit(main())
