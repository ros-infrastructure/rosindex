# encoding: UTF-8

# NOTE: This whole file is one big hack. Don't judge.

require 'pp'
require 'awesome_print'
require 'colorator'
require 'fileutils'
require 'json'
require 'rexml/document'
require 'rexml/xpath'
require 'pathname'
require 'uri'
require 'set'
require 'yaml'

# local libs
require_relative '../_ruby_libs/common'
require_relative '../_ruby_libs/rosindex'
require_relative '../_ruby_libs/conversions'
require_relative '../_ruby_libs/text_rendering'
require_relative '../_ruby_libs/pages'
require_relative '../_ruby_libs/asset_parsers'
require_relative '../_ruby_libs/lunr'
require_relative '../_ruby_libs/dependency_descriptions'

$debug = false
DEFAULT_LANGUAGE_PREFIX = 'en'
HEAVY_CHECKMARK = "\u2714"
HEAVY_MINUS = "\u2796"
DISCOVERY_RESULTS = "_artifacts/discovery.json"
DISCOVERY_ERRORS = "_artifacts/discovery_errors.json"

def get_ros_api(elem)
  return []
end

# Get a raw URI from a repo uri
def get_raw_uri(uri_s, type, branch)
  uri = URI(uri_s)

  case uri.host
  when 'github.com'
    uri_split = File.split(uri.path)
    path_split = uri_split[1].rpartition('.')
    repo_name = if path_split[1] == '.' then path_split[0] else path_split[-1] end
    return 'https://raw.githubusercontent.com/%s/%s/%s' % [uri_split[0].sub(/^\//, ''), repo_name, branch]
  when 'gitlab.com'
    uri_split = File.split(uri.path)
    path_split = uri_split[1].rpartition('.')
    repo_name = if path_split[1] == '.' then path_split[0] else path_split[-1] end
    return 'https://gitlab.com/%s/%s/-/raw/%s' % [uri_split[0].sub(/^\//, ''), repo_name, branch]
  when 'bitbucket.org'
    uri_split = File.split(uri.path)
    return 'https://bitbucket.org/%s/%s/raw/%s' % [uri_split[0], uri_split[1], branch]
  when 'code.google.com'
    uri_split = File.split(uri.path)
    return "https://#{uri_split[1]}.googlecode.com/#{type}-history/#{branch}/"
  end

  return uri_s
end

# Get a browse URI from a repo uri
def get_browse_uri(uri_s, type, branch)
  uri = URI(uri_s)

  case uri.host
  when 'github.com'
    uri_split = File.split(uri.path)
    path_split = uri_split[1].rpartition('.')
    repo_name = if path_split[1] == '.' then path_split[0] else path_split[-1] end
    return 'https://github.com/%s/%s/tree/%s' % [uri_split[0].sub(/^\//, ''), repo_name, branch]
  when 'gitlab.com'
    uri_split = File.split(uri.path)
    path_split = uri_split[1].rpartition('.')
    repo_name = if path_split[1] == '.' then path_split[0] else path_split[-1] end
    return 'https://gitlab.com/%s/%s/-/tree/%s' % [uri_split[0].sub(/^\//, ''), repo_name, branch]
  when 'bitbucket.org'
    uri_split = File.split(uri.path)
    return 'https://bitbucket.org/%s/%s/src/%s' % [uri_split[0], uri_split[1], branch]
  when 'code.google.com'
    uri_split = File.split(uri.path)
    return "https://code.google.com/p/#{uri_split[1]}/source/browse/?name=#{branch}##{type}/"
  end

  return uri_s
end

def resolve_dep(ps, ms, os, ver, data)
  # resolve rosdep
  # ps: platforms
  # ms: package managers
  # os: desired os
  # ver: desired os version
  # data: yaml data

  if data.is_a?(Array) then return data end
  if data.is_a?(Hash)
    if data.key?(os) then return resolve_dep(ps, ms, os, ver, data[os]) end
    if data.key?(ver) then return resolve_dep(ps, ms, os, ver, data[ver]) end
    if data.key?('*') then return resolve_dep(ps, ms, os, ver, data['*']) end
    if data.key?('source') and data['source'].key?('uri') then return data['source']['uri'] end
    if data.key?('packages') then return data['packages'] end
    ms.each do |manager_name, manager_oss|
      if ((manager_oss.include?(os) or manager_oss.size == 0) and data.key?(manager_name)) then return resolve_dep(ps, ms, os, ver, data[manager_name]) end
    end
  end

  return []
end

def get_package_link(platform_key, pkg_name, version_key)
  # get a link for info on pkg_name on platform platform_key
  case platform_key
  when 'ubuntu'
    if ['noble', 'jammy', 'plucky', 'questing', 'resolute'].include?(version_key) then
      return "https://packages.ubuntu.com/#{version_key}/#{pkg_name}"
    else
      return nil
    end
  when 'debian'
    if ['bullseye', 'bookworm', 'trixie', 'forky','sid'].include?(version_key) then
      return "https://packages.debian.org/#{version_key}/#{pkg_name}"
    else
      return nil
    end
  when 'fedora'
    if ['41', '42', '43'].include?(version_key) then
      return "https://packages.fedoraproject.org/pkgs/#{pkg_name}/#{pkg_name}/"
    else
      return nil
    end
  when 'osx'
    return "https://formulae.brew.sh/formula/#{pkg_name}"
  end

  return nil
end

def expand_package_deps(package_name, package_names, deps, distro)
  # Expand package dependencies at all levels for package_name.
  if deps.include?(package_name)
    return
  end
  deps.add(package_name)
  if not package_names.key?(package_name)
    return
  end
  if not package_names[package_name].snapshots.key?(distro)
    return
  end
  package_snapshot = package_names[package_name].snapshots[distro]
  if package_snapshot
    package_snapshot.data['pkg_deps'].keys.each do |dep_name|
      expand_package_deps(dep_name, package_names, deps, distro)
    end
  end
end

class Indexer < Jekyll::Generator
  def initialize(config = {})
    super(config)

    # lunr search config
    lunr_config = {
      'excludes' => [],
      'strip_index_html' => false,
      'min_length' => 3,
      'stopwords' => '_stopwords/stop-words-english1.txt'
    }.merge!(config['lunr_search'] || {})
    # lunr excluded files
    @excludes = lunr_config['excludes']
    # if web host supports index.html as default doc, then optionally exclude it from the url
    @strip_index_html = lunr_config['strip_index_html']
    # stop word exclusion configuration
    @min_length = lunr_config['min_length']
    @stopwords_file = lunr_config['stopwords']
    if File.exist?(@stopwords_file)
      @stopwords = IO.readlines(@stopwords_file, :encoding=>'UTF-8').map { |l| l.strip }
    else
      @stopwords = []
    end
  end

  def map_build_result_to_icon(build_result)
    if build_result == 'success'
      return 'ok'
    end
    if build_result == 'unstable' || build_result == 'not_built'
      return 'minus'
    end
    if build_result == 'failure' || build_result == 'aborted'
      return 'remove'
    end
    # TODO: use better icon for unknown build statuses
    return 'remove'
  end


  def extract_package(site, distro, repo, snapshot, pkg_cache, pkg_type, manifest_xml)

    data = snapshot.data
    pkg_cache ||= {}

    begin
      # switch basic info based on build type
      if pkg_type == 'catkin'
        # read the package manifest
        manifest_doc = REXML::Document.new(manifest_xml)
        package_name = REXML::XPath.first(manifest_doc, "/package/name/text()").to_s.strip
        version = REXML::XPath.first(manifest_doc, "/package/version/text()").to_s.strip

        # if a build type (e.g. ament_python for ROS 2) has been declared explicitly, use that as the package type
        build_type = REXML::XPath.first(manifest_doc, "/package/export/build_type/text()").to_s.strip
        unless build_type.length == 0
          pkg_type = build_type
        end

        # get dependencies
        deps = REXML::XPath.each(
          manifest_doc,
          "/package/build_depend/text() | " +
          "/package/build_export_depend/text() | " +
          "/package/buildtool_depend/text() | " +
          "/package/buildtool_export_depend/text() | " +
          "/package/exec_depend/text() | " +
          "/package/doc_depend/text() | " +
          "/package/run_depend/text() | " +
          "/package/test_depend/text() | " +
          "package/depend/text()"
        ).map { |a| a.to_s.strip }.uniq

        # determine which deps are packages or system deps
        pkg_deps = {}
        system_deps = {}

        deps.each do |dep_name|
          if @rosdeps.key?(dep_name)
            system_deps[dep_name] = nil
          else
            pkg_deps[dep_name] = nil
          end
        end

      elsif pkg_type == 'rosbuild'
        package_name = (pkg_cache['name'] || File.basename(pkg_cache['package_path'].to_s)).strip
        version = (pkg_cache['version'] || "UNKNOWN").to_s.strip

        # read the package manifest
        manifest_doc = REXML::Document.new(manifest_xml)

        # get dependencies
        pkg_deps = Hash[*REXML::XPath.each(manifest_doc, "/package/depend/@package").map { |a| a.to_s.strip }.uniq.collect {|d| [d, nil]}.flatten]
        system_deps = Hash[*REXML::XPath.each(manifest_doc, "/package/rosdep/@name").map { |a| a.to_s.strip }.uniq.collect {|d| [d, nil]}.flatten]
      else
        return nil
      end

      package_relpath = (pkg_cache['package_path'] || '').to_s.strip
      package_relpath = '.' if package_relpath.empty?

      dputs " ---- Found #{pkg_type} package \"#{package_name}\" in path #{package_relpath}"

      # extract manifest metadata (same for manifest.xml and package.xml)
      license = REXML::XPath.first(manifest_doc, "/package/license/text()").to_s
      description = REXML::XPath.first(manifest_doc, "/package/description/text()").to_s
      maintainers = REXML::XPath.each(manifest_doc, "/package/maintainer/text()").map { |m| m.to_s.sub('@', ' <AT> ') }
      authors = REXML::XPath.each(manifest_doc, "/package/author/text()").map { |a| a.to_s.sub('@', ' <AT> ') }
      urls = REXML::XPath.each(manifest_doc, "/package/url").map { |elem|
        {
          'uri' => elem.text.to_s,
          'type' => (elem.attributes['type'] or 'Website').to_s,
        }
      }

      # extract other standard exports
      deprecated = REXML::XPath.first(manifest_doc, "/package/export/deprecated/text()").to_s

      # extract package manifest info
      if package_relpath == '.'
        raw_uri = data['raw_uri']
        browse_uri = data['browse_uri']
      else
        raw_uri = File.join(data['raw_uri'], package_relpath)
        browse_uri = File.join(data['browse_uri'], package_relpath)
      end

      # Render cached readmes for this package
      readmes = Array.new
      cached_readme_entries = []

      if pkg_cache['readmes'].is_a?(Hash)
        pkg_cache['readmes'].each do |relpath, content|
          cached_readme_entries << [relpath.to_s, content]
        end
      elsif pkg_cache['readmes'].is_a?(Array)
        pkg_cache['readmes'].each do |entry|
          if entry.is_a?(Hash)
            cached_readme_entries << [(entry['relpath'] || entry['filename'] || 'README.md').to_s, entry['content'] || entry['readme']]
          end
        end
      end

      if pkg_cache['readme']
        readme_filename = (pkg_cache['readme_filename'] || 'README.md').to_s
        unless cached_readme_entries.any? { |relpath, _| relpath == readme_filename }
          cached_readme_entries << [readme_filename, pkg_cache['readme']]
        end
      end

      cached_readme_entries.each do |readme_relpath, readme_content|
        tmp_readme_rendered, tmp_readme = render_cached_doc(site, readme_content, readme_relpath, raw_uri, browse_uri)
        readme = {
          'browse_uri' => File.join(browse_uri, readme_relpath),
          'readme' => tmp_readme,
          'readme_rendered' => tmp_readme_rendered,
          'relpath' => (package_relpath == '.' ? readme_relpath : File.join(package_relpath, readme_relpath))
        }
        readmes.push(readme)
      end
      readmes.reject! do |x|
        x['readme'].nil? || x['readme_rendered'].nil?
      end

      # Render cached changelog for this package
      changelog_filename = (pkg_cache['changelog_filename'] || 'CHANGELOG.rst').to_s
      changelog_rendered, changelog = render_cached_doc(
        site, pkg_cache['changelog'], changelog_filename, raw_uri, browse_uri)

      # Extract cached launch, msg, srv, and plugin assets
      launch_errors = []
      launch_data = extract_launch_data(pkg_cache['launch_files'], launch_errors)
      @errors[repo.name].concat(launch_errors) unless launch_errors.empty?
      msg_files = (pkg_cache['msg_files'] || []).map(&:to_s)
      srv_files = (pkg_cache['srv_files'] || []).map(&:to_s)
      action_files = (pkg_cache['action_files'] || []).map(&:to_s)
      plugin_data = REXML::XPath.each(manifest_doc, '//export/*[@plugin]').map {|e| {'name'=>e.name, 'file'=>e.attributes['plugin'].sub('${prefix}','')}}

      if $ros_distros.include? distro
        # ROS 1
        docs_uri = "http://docs.ros.org/#{DEFAULT_LANGUAGE_PREFIX}/#{distro}/api/#{package_name}/html/"
      else
        # ROS 2
        docs_uri = "http://docs.ros.org/#{DEFAULT_LANGUAGE_PREFIX}/#{distro}/p/#{package_name}"
      end


      package_info = {
        'name' => package_name,
        'pkg_type' => pkg_type,
        'distro' => distro,
        'raw_uri' => raw_uri,
        'browse_uri' => browse_uri,
        'docs_uri' => docs_uri,
        # required package info
        'version' => version,
        'license' => license,
        'description' => description,
        'maintainers' => maintainers,
        # optional package info
        'authors' => authors,
        'urls' => urls,
        # dependencies
        'pkg_deps' => pkg_deps,
        'system_deps' => system_deps,
        'dependants' => {},
        # exports
        'deprecated' => deprecated,
        # readme
        'readmes' => readmes,
        # changelog
        'changelog' => changelog,
        'changelog_rendered' => changelog_rendered,
        # assets
        'launch_data' => launch_data,
        'plugin_data' => plugin_data,
        'msg_files' => msg_files,
        'srv_files' => srv_files,
        'action_files' => action_files,
      }

    rescue REXML::ParseException => e
      @errors[repo.name] << IndexException.new("Failed to parse package manifest: " + e.to_s)
      return nil
    end

    return package_info
  end

  # index cached packages and documentation for a repository snapshot
  def index_cached_version(site, repo, distro, snapshot)

    unless repo.uri
      puts ("WARNING: no URI for "+repo.name+" "+repo.id+" "+distro).yellow
      return
    end

    cached = snapshot.cached_data || {}
    raw_uri = get_raw_uri(repo.uri, repo.type, snapshot.version)
    browse_uri = get_browse_uri(repo.uri, repo.type, snapshot.version)

    readme_rendered, readme = render_cached_doc(
      site, cached['readme'], cached['readme_filename'] || 'README.md', raw_uri, browse_uri)
    contributing_rendered, _ = render_cached_doc(
      site, cached['contributing'], cached['contributing_filename'] || 'CONTRIBUTING.md', raw_uri, browse_uri)

    # initialize this snapshot data
    data = snapshot.data = {
      # get the uri for resolving raw links (for images, etc)
      'raw_uri' => raw_uri,
      'browse_uri' => browse_uri,
      # get the date of the last modification
      'last_commit_time' => cached['last_commit_time'],
      'readme' => readme,
      'readme_rendered' => readme_rendered,
      'contributing_rendered' => contributing_rendered
    }

    packages = {}
    cached_packages = cached['packages'] || {}
    if cached_packages.any?
      cached_packages.each do |pkg_name, pkg_cache|
        manifest_xml = pkg_cache['package.xml']
        next if manifest_xml.nil? || manifest_xml.empty?
        package_info = extract_package(site, distro, repo, snapshot, pkg_cache, 'catkin', manifest_xml)
        unless package_info.nil?
          packages[package_info['name']] = package_info
          dputs " -- added package " << package_info['name']
        end
      end
    elsif !repo.release_manifests[distro].nil?
      pkg_cache = {'package_path' => '', 'package.xml' => repo.release_manifests[distro]}
      package_info = extract_package(site, distro, repo, snapshot, pkg_cache, 'catkin', repo.release_manifests[distro])
      unless package_info.nil?
        packages[package_info['name']] = package_info
      end
    end

    # add the discovered packages to the index
    packages.each do |package_name, package_data|
      # create a new package snapshot
      package = PackageSnapshot.new(package_name, repo, snapshot, package_data)

      # store this package in the repo snapshot
      snapshot.packages[package_name] = package

      # add this package to the global package dict
      @package_names[package_name].instances[repo.id] = repo

      # add this package as the default for this distro
      if @repo_names[repo.name].defaults[distro]
        dputs " --- Adding packages to repo " << repo.id << "as default for package " << package_name << " in distro " << distro
        @package_names[package_name].repos[distro] = repo
        @package_names[package_name].snapshots[distro] =  package
      end
    end
  end

  def index_cached_repo(site, repo, progress_prefix = nil)
    prefix = progress_prefix ? "#{progress_prefix} " : ""

    if @domain_blacklist.include? URI(repo.uri).hostname
      msg = "Repo instance " + repo.id + " has a blacklisted hostname: " + repo.uri.to_s
      puts ("#{prefix}WARNING: #{msg}").yellow
      repo.errors << msg
      return
    end

    found_distros = []
    ignored_distros = []
    missing_distros = []
    pkg_names = Set.new

    # index cached data for each distro snapshot
    repo.snapshots.each do |distro, snapshot|
      version = snapshot.version
      if version
        if snapshot.cached_data && snapshot.cached_data['ignored']
          ignored_distros << distro
          snapshot.version = nil
        else
          found_distros << distro
          index_cached_version(site, repo, distro, snapshot)
          pkg_names.merge(snapshot.packages.keys)
        end
      else
        missing_distros << distro
      end
    end

    summary_parts = [
      "found=[#{found_distros.join(', ')}]",
      "ignored=#{ignored_distros.empty? ? 0 : "[#{ignored_distros.join(', ')}]"}",
      "missing=#{missing_distros.empty? ? 0 : "[#{missing_distros.join(', ')}]"}",
      "packages=#{pkg_names.size}"
    ]
    puts "#{prefix}Indexing cached repo #{repo.name} (#{repo.id}): #{summary_parts.join(', ')}".blue

    if found_distros.empty?
      msg = "Could not find any valid version."
      @errors[repo.name] << IndexException.new(msg, repo.id)
      repo.errors << (repo.id+': '+msg)
    end

  end

  class SystemDep < Liquid::Drop
    # This represents a system dependency ("rosdep")
    attr_accessor :name, :repo, :snapshot, :version, :data
    def initialize(name, repo, snapshot, data)
      @name = name

      # TODO: get rid of these back-pointers
      @repo = repo
      @snapshot = snapshot
      @version = snapshot.version

      # additionally-collected data
      @data = data
    end
  end

  def load_rosdeps(rosdistro_path, platforms, package_manager_names)
    # this returns 
    # see here for parsing this thing: http://www.ros.org/reps/rep-0111.html

    rosdep_data = Hash.new

    manager_set = Set.new(package_manager_names)

    Dir.glob(File.join(rosdistro_path,'rosdep','*.yaml')) do |rosdep_filename|
      rosdep_yaml = YAML.load_file(rosdep_filename, aliases: true)
      rosdep_data = rosdep_data.deep_merge(rosdep_yaml)
    end

    # update the platforms list
    new_platforms = {}

    # look for new platforms and versions
    rosdep_data.each do |name, deps|
      # iterate over platform names
      deps.each do |platform_name, platform_deps|

        if package_manager_names.include? platform_name then next end
        unless new_platforms.key?(platform_name) then new_platforms[platform_name] = {'versions'=>[]} end
        unless platform_deps.is_a?(Hash) then next end
        if platform_deps.key?('packages') then next end
        if platform_deps.key?('source') then next end
        if manager_set.intersection(platform_deps.keys).length > 0 then next end

        # iterate over version names
        platform_deps.each do |version_or_manager_name, version_deps|
          # add this version name
          new_platforms[platform_name]['versions'] |= [version_or_manager_name]
        end
      end
    end

    dputs "New Platforms: "
    dputs YAML.dump(new_platforms)

    return rosdep_data
  end

  def generate_search_deps_list(site)
    site.pages << SearchDepsListPage.new(site)
  end

  def write_release_manifests(site, repo, package_name, default)
    $all_distros.each do |distro|
      unless repo.release_manifests[distro].nil?
        manifest_path = File.join('p', package_name, unless default then repo.id else '' end, distro)
        dest_manifest_path = File.join(site.dest,manifest_path)

        unless File.exist?(dest_manifest_path) or File.directory?(dest_manifest_path) then FileUtils.mkdir_p(dest_manifest_path) end

        IO.write(File.join(dest_manifest_path,'package.xml'), repo.release_manifests[distro])
        site.static_files << PackageManifestFile.new(site, site.dest, '/'+manifest_path, 'package.xml')
      end
    end
  end

  def strip_stopwords(text)
    begin
      text = text.encode('UTF-16', :undef => :replace, :invalid => :replace, :replace => "??").encode('UTF-8').split.delete_if() do |x|
        t = x.downcase.gsub(/[^a-z']/, '')
        t.length < @min_length || @stopwords.include?(t)
      end.join(' ')
    rescue ArgumentError
      puts text.encode('UTF-16', :undef => :replace, :invalid => :replace, :replace => "??").encode('UTF-8')
      throw
    end
  end

  def generate(site)

    # construct list of known ros distros
    $recent_distros = site.config['distros']
    $all_distros = site.config['distros'] + site.config['old_distros']
    $ros_distros = site.config['ros_distros'] +
                    site.config['old_ros_distros']
    $ros2_distros = site.config['ros2_distros'] +
                    site.config['old_ros2_distros']

    @domain_blacklist = site.config['domain_blacklist']

    @db_cache_filename = if site.config['db_cache_filename'] then site.config['db_cache_filename'] else 'rosindex.db' end
    @use_db_cache = (site.config['use_db_cache'] and File.exist?(@db_cache_filename))

    @skip_scrape = site.config['skip_scrape']

    if @use_db_cache
      puts ("Reading cache: " << @db_cache_filename).blue
      @db = Marshal.load(IO.read(@db_cache_filename))
    else
      @db = RosIndexDB.new
    end

    # rosdeps
    @rosdeps = @db.rosdeps
    # the global index of repos
    @all_repos = @db.all_repos
    # the list of repo instances by name
    @repo_names = @db.repo_names
    # the list of package instances by name
    @package_names = @db.package_names
    # the list of errors encountered
    @errors = @db.errors

    # load rosdep data
    puts ("Loading ros dependencies").green

    # TODO: check deps against this when generating pages
    rosdep_path = site.config['rosdep_path'] || '_remotes/rosdep'

    raw_rosdeps = load_rosdeps(
      rosdep_path,
      site.data['common']['platforms'],
      site.data['common']['package_manager_names'].keys)

    debian_descriptions = get_debian_descriptions()
    pip_descriptions = get_pip_descriptions()

    raw_rosdeps.each do |dep_name, dep_data|
      platforms = site.data['common']['platforms']
      manager_set = Set.new(site.data['common']['package_manager_names'])
      description = ""

      platform_data = {}
      platforms.each do |platform_key, platform_details|
        if platform_details['versions'].size > 0
          platform_data[platform_key] = {}
          platform_details['versions'].each_key do |version_key|
            packages = resolve_dep(platforms, manager_set, platform_key, version_key, dep_data)
            if packages.is_a?(Array)
              platform_data[platform_key][version_key] = packages.map { |pkg_name|
                [pkg_name, get_package_link(platform_key, pkg_name, version_key)]
              }
            else
              # probably an old source entry, see libaria on debian Wheezy
              platform_data[platform_key][version_key] = [[packages, nil]]
            end
          end
          # Get dep description from debian
          if platform_key == 'debian'
            platform_data[platform_key]['bullseye'].each do |key_and_link|
              debian_key = key_and_link[0]
              # zero-length debian_descriptions indicates a failed download
              if debian_descriptions.length > 0
                if debian_descriptions.has_key?(debian_key)
                  description = debian_descriptions[debian_key]
                  break
                end
              elsif site.config['use_db_cache'] and
                  @rosdeps.has_key? dep_name and
                  @rosdeps[dep_name].has_key? 'description'
                description = @rosdeps[dep_name]['description']
                break
              end
            end
          end
        else
          packages = resolve_dep(platforms, manager_set, platform_key, 'any_version', dep_data)
          # all platforms that don't have versions currently don't have links available
          platform_data[platform_key] = packages.map { |pkg_name|
            [pkg_name, nil]
          }
        end
      end
      # if debian did not get a description, maybe we got it from pip
      if description.empty? and pip_descriptions.has_key?(dep_name)
        description = pip_descriptions[dep_name]
      end
      @rosdeps[dep_name] = {'data_per_platform' => platform_data, 'dependants_per_distro' => {}, 'description' => description}
    end

    # get the repositories from the rosdistro files, rosdoc rosinstall files, and other sources
    discovery_errors = {}
    if File.exist?(DISCOVERY_RESULTS)
      puts ("Loading discovered repos from a file").green
      repos = File.open(DISCOVERY_RESULTS, 'r') { |f| JSON.load(f) }
      if File.exist?(DISCOVERY_ERRORS)
        discovery_errors = File.open(DISCOVERY_ERRORS, 'r') { |f| JSON.load(f) }
      end
    else
      raise RuntimeError.new("Discovery results file #{DISCOVERY_RESULTS} not found. Run 'make discover' first.")
    end
    discovery_errors.each do |distro, vals|
      vals.each { |val| @errors[distro].push(IndexException.new(val["msg"], val["repo_id"])) }
    end

    # Create repo objects from cached discovery data
    repos.each do |distro, repo_list|
      next if repo_list.empty?
      new_repos_in_distro = 0
      repo_list.each do |repo_item|
        # limit repos if requested
        unless (site.config['repo_name_whitelist'].length == 0 or site.config['repo_name_whitelist'].include?(repo_item['name'])) then next end
        if not site.config['repo_name_always'].include?(repo_item['name']) and \
          not @repo_names.has_key?(repo_item['name']) and site.config['max_repos'] > 0 and @repo_names.length > site.config['max_repos'] then next end

        begin
          repo = Repo.new(
            repo_item['name'],
            repo_item['type'],
            repo_item['uri'],
            'Via rosdistro: '+distro)
        rescue
            raise IndexException.new("Failed to create repo from #{repo_item['type']} repo #{repo_item['uri']}: " + repo_item['name'])
        end

        # create a new repo structure for this remote
        if @all_repos.key?(repo.id)
          repo = @all_repos[repo.id]
        else
          dputs " -- Adding repo " << repo.name << " instance: " << repo.id << " from uri: " << repo.uri.to_s << " with version: " << repo_item['version']
          # store this repo in the unique index
          @all_repos[repo.id] = repo
          new_repos_in_distro += 1
        end

        # get maintainer status
        repo.status = repo_item['status']
        if repo_item['tags'].is_a?(Array)
          repo.tags |= repo_item['tags']
        end

        cached_data = {
          'last_commit_time' => repo_item['last_commit_time'],
          'readme' => repo_item['readme'],
          'readme_filename' => repo_item['readme_filename'] || 'README.md',
          'contributing' => repo_item['contributing'],
          'contributing_filename' => repo_item['contributing_filename'] || 'CONTRIBUTING.md',
          'stars' => repo_item['stars'],
          'description' => repo_item['description'],
          'tags' => repo_item['tags'] || [],
          'ignored' => repo_item['ignored'] || false,
          'packages' => repo_item['packages'] || {}
        }

        # add the specific version from this instance
        repo.snapshots[distro] = RepoSnapshot.new(repo_item['version'], distro, repo_item['release'], true, cached_data)

        # add the release manifest, if found
        repo.release_manifests[distro] = repo_item['manifest']

        # store this repo in the name index
        @repo_names[repo.name].instances[repo.id] = repo
        @repo_names[repo.name].defaults[distro] = repo
      rescue IndexException => e
        @errors[repo_item['name']] << e
      end
      puts ("Loaded rosdistro #{distro} from discovery cache: #{repo_list.length} entries (#{new_repos_in_distro} new repo instances)").green
    end

    puts "Found " << @all_repos.length.to_s << " repositories corresponding to " << @repo_names.length.to_s << " repo identifiers."

    # index cached packages and docs for all repos
    unless @skip_scrape
      n_indexed = 0
      n_total = @all_repos.length
      puts "Indexing cached data for #{n_total} repositories...".green
      @all_repos.to_a.sort_by{|repo_id, repo| repo.name}.each do |repo_id, repo|
        unless (site.config['repo_name_whitelist'].length == 0 or site.config['repo_name_whitelist'].include?(repo.name)) then next end
        if site.config['repo_id_whitelist'].size == 0 or site.config['repo_id_whitelist'].include?(repo.id)

          progress_prefix = "[%05.2f%%]" % (n_indexed / n_total.to_f * 100.0)
          begin
            index_cached_repo(site, repo, progress_prefix)
          rescue IndexException => e
            @errors[repo.name] << e
            repo.errors << e.msg
          end
          n_indexed = n_indexed + 1
        end
      end
    end

    if site.config['use_db_cache']
      # backup the current db if it exists
      if File.exist?(@db_cache_filename) then FileUtils.mv(@db_cache_filename, @db_cache_filename+'.bak') end
      # save indexed data into the cache db
      db_cache_dirname = File.dirname(@db_cache_filename)
      Dir.mkdir(db_cache_dirname) unless File.directory?(db_cache_dirname)
      File.open(@db_cache_filename, 'w') {|f| f.write(Marshal.dump(@db)) }
    end

    puts "Generating update report...".blue

    # read the old report
    old_report = {}
    old_report_filename = site.config['report_filename']
    if File.exist?(old_report_filename)
      old_report = YAML.load(IO.read(old_report_filename), aliases: true)
    end

    # write out the report and the diff
    new_report = @db.get_report
    report_yaml = new_report.to_yaml
    report_filename = 'index_report.yaml'

    if not File.directory?(site.dest)
      Dir.mkdir(site.dest)
    end

    File.open(File.join(site.dest, report_filename),'w+') {|f| f.write(report_yaml) }
    site.static_files << ReportFile.new(site, site.dest, "/", report_filename)
    report_dirname = File.dirname(site.config['report_filename'])
    Dir.mkdir(report_dirname) unless File.directory?(report_dirname)
    File.open(site.config['report_filename'],'w') {|f| f.write(report_yaml) }

    if not old_report.empty?
      report_diff = @db.diff_report(old_report, new_report)
      report_yaml = report_diff.to_yaml
      report_filename = 'index_report_diff.yaml'
      File.open(File.join(site.dest, report_filename),'w') {|f| f.write(report_yaml) }
      site.static_files << ReportFile.new(site, site.dest, "/", report_filename)
      report_diff_dirname = File.dirname(site.config['report_diff_filename'])
      Dir.mkdir(report_diff_dirname) unless File.directory?(report_diff_dirname)
      File.open(site.config['report_diff_filename'],'w') {|f| f.write(report_yaml) }
    end

    # compute post-scrape details
    # TODO: check for missing deps or just leave them as nil?
    @repo_names.each do |repo_name, repo_instances|
      repo_instances.instances.each do |instance_id, repo|
        repo.snapshots.each do |distro, snapshot|
          snapshot.packages.each do |package_name, package_snapshot|
            # add package details
            package_snapshot.data['pkg_deps'].keys.each do |dep_name|
              if @package_names.key?(dep_name)
                # add forward dep
                # forward deps should point to the package instances page,
                # since it might be any given instance
                package_snapshot.data['pkg_deps'][dep_name] = @package_names[dep_name]
              end

              # add reverse dep to each dep
              # reverse deps can point to the exact instance which depends on this package
              # these are keyed by package name => list of instances
              @package_names[dep_name].instances.each do |dep_instance_id, dep_repo|
                if not dep_repo.snapshots[distro]
                  dputs " - Skipping dep_repo.snapshots["+distro+"] TODO(tfoote) Not sure who"
                  next
                end
                if dep_repo.snapshots[distro].packages.key?(dep_name)
                  dependants = dep_repo.snapshots[distro].packages[dep_name].data['dependants']
                  unless dependants.key?(package_name) then dependants[package_name] = [] end
                  dependants[package_name] << {
                    'repo' => repo,
                    'id' => instance_id,
                    'package' => package_snapshot
                  }
                end
              end
            end
            # add rosdep details
            package_snapshot.data['system_deps'].keys.each do |dep_name|
              if @rosdeps.key?(dep_name)
                package_snapshot.data['system_deps'][dep_name] = @rosdeps[dep_name]
                dep_dependants_per_distro = @rosdeps[dep_name]['dependants_per_distro']
                unless dep_dependants_per_distro.key?(distro) then
                  dep_dependants_per_distro[distro] = []
                end
                dep_dependants_per_distro[distro] << {
                  'repo' => repo,
                  'id' => instance_id,
                  'package' => package_snapshot
                }
              end
            end
          end
        end
      end
    end

    # generate pages for all repos
    @repo_names.each do |repo_name, repo_instances|

      # create the repo pages
      dputs " - creating pages for repo "+repo_name+"..."

      # create the page for the default instance
      site.pages << RepoPage.new(site, repo_instances)

    end

    # create package pages
    puts ("Found "+String(@package_names.length)+" packages total.").green
    puts ("Generating package pages...").blue

    @package_names.each do |package_name, package_instances|

      dputs "Generating pages for package " << package_name << "..."

      # create default package page
      site.pages << PackagePage.new(site, package_instances)
    end

    # create system dependency list pages
    puts ("Generating system dependency list pages...").blue

    generate_search_deps_list(site)

    # create rosdep pages
    puts ("Generating rosdep pages...").blue

    rosdep_count = 0
    @rosdeps.each do |dep_name, full_dep_data|
      site.pages << DepPage.new(site, dep_name, raw_rosdeps[dep_name], full_dep_data)
      rosdep_count += 1
      break if site.config.has_key?('max_rosdeps') && rosdep_count >= site.config['max_rosdeps']
    end

    # populate the home page with available distros
    site.pages << HomePage.new(site)

    core_deps = {}
    # create lunr index data
    unless site.config['skip_search_index']
      puts ("Generating packages search index...").blue

      # Determine which packages are dependencies of core packages.
      core_packages = ['ros_core', 'ros_base', 'desktop', 'desktop_full']
      $all_distros.each do |distro|
        core_deps[distro] = {}
        core_packages.each do |parent_name|
          deps = Set.new()
          expand_package_deps(parent_name, @package_names, deps, distro)
          core_deps[distro][parent_name] = deps
        end
      end

      packages_index = {}
      $all_distros.each do |distro|
        packages_index[distro] = []
      end

      index = 0
      @all_repos.each do |instance_id, repo|
        repo.snapshots.each do |distro, repo_snapshot|

          if repo_snapshot.version == nil then next end

          repo_snapshot.packages.each do |package_name, package|

            if package.nil? then next end

            p = package.data

            # collect rendered readmes into simple text
            readmes_text = ''
            p['readmes'].each do |readme|
              readmes_text << get_text_from_html(readme['readme_rendered'])
            end

            readme_filtered = self.strip_stopwords(readmes_text)

            index += 1
            core = ''
            core_packages.each do |parent_name|
              if core.empty? and core_deps[distro][parent_name].include?(package_name) then
                core = parent_name
              end
            end
            packages_index[distro] << {
              'id' => index,
              'baseurl' => site.config['baseurl'],
              'url' => File.join('/p',package_name)+"#"+distro,
              'last_commit_time' => repo_snapshot.data['last_commit_time'],
              'tags' => (package_name.split('_')) * " ",
              'package' => package_name,
              'repo' => repo.name,
              'core' => core,
              'released' => if repo_snapshot.released then 'released' else '' end,
              'version' => p['version'],
              'description' => p['description'].strip,
              'maintainers' => p['maintainers'] * ", ",
              'authors' => p['authors'] * ", ",
              'distro' => distro,
              'pkg_deps' => p['pkg_deps'].length,
              'dependants' => p['dependants'].length,
              'readme' => readme_filtered,
              'org' => URI(repo.uri).path.split('/')[1]
            }

            dputs 'indexed: ' << "#{package_name} #{instance_id} #{distro}"
          end
        end
      end

      puts ("Precompiling lunr index for packages...").blue
      reference_field = 'id'
      indexed_fields = [
        'tags:100', 'package:100', 'description:50', 'maintainers', 'authors',
        'readme', 'released', 'org', 'repo', 'core'
      ]
      site.static_files.push(*precompile_lunr_index(
        site, packages_index, reference_field, indexed_fields,
        "search/packages/", $all_distros
      ).to_a)

      puts ("Generating system dependencies search index...").blue

      system_deps_index = []
      @rosdeps.each do |dep_name, full_dep_data|
        dependants_per_distro = full_dep_data['dependants_per_distro']
        usage = 0
        dependants_per_distro.each do |_, platform_usage|
          usage += platform_usage.length
        end
        data_per_platform = full_dep_data['data_per_platform']
        aliases = Set[]

        system_deps_index_item = {
          'id' => system_deps_index.length,
          'url' => File.join('/d', dep_name),
          'name' => dep_name,
          'description' => full_dep_data['description'] || '',
          'usage' => usage,
          'score': 0.0,
          # The lunr tokenizr by default splits strings into tokens, using a default separator
          # of ' ' and '-'. So we do not need to add these tags to the index for search purposes.
          # 'tags' => dep_name.split('-') * " ",
          'platforms' => data_per_platform.collect do |platform_key, data|
            next if data.empty?
            next unless site.data['common']['platforms'].key? platform_key
            platform_details = site.data['common']['platforms'][platform_key]
            platform_name = platform_details['name']
            platform_versions = platform_details['versions']
            if platform_versions.size > 0
              data.collect do |version_key, names_for_version|
                next unless names_for_version.is_a? Array
                next unless platform_versions.key? version_key
                next if names_for_version.empty?
                version_name = platform_versions[version_key]
                if version_name.empty?
                  version_name = version_key.capitalize
                end
                names_for_version.collect do |name_and_link|
                  aliases.add(name_and_link[0])
                  "#{name_and_link[0]} (#{platform_name} #{version_name})"
                end.join(' : ')
              end.compact.join(' : ')
            else
              data.collect do |name_and_link|
                aliases.add(name_and_link[0])
                "#{name_and_link[0]} (#{platform_name})"
              end.join(' : ')
            end
          end.compact.join(' : '),
          'aliases' => aliases.to_a.join(' '),
          'dependants' => dependants_per_distro.collect do |distro, dependants|
            next if dependants.empty?
            dependants.map do |dependant|
              dependant['package'].name
            end.join(' : ')
          end.compact.join(' : ')
        }

        platform_availables = []

        site.data['common']['current_platforms'].each do |cp, platform_name|
          versions = site.data['common']['platforms'][cp]['versions']
          found_all = true
          found_one = false
          dep_platform = data_per_platform[cp]
          n_versions = versions.size
          if n_versions > 0
            versions.keys.each do |v|
              dep_version = dep_platform[v]
              n_deps = dep_version.size
              if n_deps > 0
                found_one = true
              else
                found_all = false
              end
            end
          else
            n_deps = dep_platform.size
            if n_deps > 0
              found_one = true
            else
              found_all = false
            end
          end

          if found_all
            availability = HEAVY_CHECKMARK
          elsif found_one
            availability = HEAVY_MINUS
          else
            availability = ''
          end

          if found_one or found_all
            platform_availables << cp
            if cp.downcase != platform_name.downcase
              platform_availables << platform_name
            end
          end

          system_deps_index_item[cp] = availability
        end

        # Calculate dep availability per platform. Add both platform key and name to a searchable
        # field to allow searching, for example, for "RHEL".
        system_deps_index_item['platforms'] = platform_availables.join(' ')
        system_deps_index << system_deps_index_item
      end

      puts ("Precompiling lunr index for system dependencies...").blue
      reference_field = 'id'
      # indexed_fields = ['name', 'platforms', 'dependants', 'description', 'aliases']
      indexed_fields = ['name', 'description', 'dependants', 'aliases', 'platforms']
      deps_shards = 1
      slice_length = system_deps_index.length / deps_shards || 1
      slices = {}
      system_deps_index.each_slice(slice_length).with_index.map { |item, i| slices[i.to_s] = item }
      site.static_files.push(*precompile_lunr_index(
        site, slices, reference_field, indexed_fields,
        "search/deps/", slices.keys
      ).to_a)
    end

    # create stats page
    puts "Generating statistics page...".blue
    site.pages << StatsPage.new(site, @package_names, @all_repos, @errors)

    # create errors page
    puts "Generating errors page...".blue
    site.pages << ErrorsPage.new(site, @errors)

    # remove symlinks in js to workaround issue #422
    Dir.glob(File.join(site.dest, 'js', '*.js')) do |filename|
       File.delete(filename) if File.symlink?(filename)
       # needed for js/venn.js/venn.js
       FileUtils.rm_rf(filename) if File.directory?(filename)
    end

  end

end
