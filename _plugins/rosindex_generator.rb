# encoding: UTF-8

# NOTE: This whole file is one big hack. Don't judge.

require 'pp'
require 'awesome_print'
require 'colorator'
require 'fileutils'
require 'find'
require 'json'
require 'rexml/document'
require 'rexml/xpath'
require 'pathname'
require 'uri'
require 'set'
require 'yaml'
require "net/http"
require 'thread'

# local libs
require_relative '../_ruby_libs/common'
require_relative '../_ruby_libs/rosindex'
require_relative '../_ruby_libs/vcs'
require_relative '../_ruby_libs/conversions'
require_relative '../_ruby_libs/text_rendering'
require_relative '../_ruby_libs/pages'
require_relative '../_ruby_libs/asset_parsers'
require_relative '../_ruby_libs/lunr'
require_relative '../_ruby_libs/dependency_descriptions'
require_relative '../_ruby_libs/discovery'

$fetched_uris = {}
$debug = false
DEFAULT_LANGUAGE_PREFIX = 'en'
HEAVY_CHECKMARK = "\u2714"
HEAVY_MINUS = "\u2796"
DISCOVERY_RESULTS = "_artifacts/discovery.json"
DISCOVERY_ERRORS = "_artifacts/discovery_errors.json"

def get_ros_api(elem)
  return []
end

def get_readme(site, path, raw_uri, browse_uri)
  return get_md_rst_txt(site, path, "README*", raw_uri, browse_uri)
end

def get_contributing(site, path, raw_uri, browse_uri)
  return get_md_rst_txt(site, path, "CONTRIBUTING*", raw_uri, browse_uri)
end

def get_changelog(site, path, raw_uri, browse_uri)
  return get_md_rst_txt(site, path, "CHANGELOG*", raw_uri, browse_uri)
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
    if data.key?('source') and data['source'].key?('uri') then return data['source']['uri'] end
    if data.key?('packages') then return data['packages'] end
    ms.each do |manager_name, manager_oss|
      if ((manager_oss.include?(os) or manager_oss.size == 0) and data.key?(manager_name)) then return resolve_dep(ps, ms, os, ver, data[manager_name]) end
    end
  end

  return []
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

  def update_local(site, repo_instances)

    # add / fetch all the instances
    repo_instances.instances.each do |id, repo|

      begin
        unless (site.config['repo_name_whitelist'].length == 0 or site.config['repo_name_whitelist'].include?(repo.name)) then next end
        unless site.config['repo_id_whitelist'].size == 0 or site.config['repo_id_whitelist'].include?(repo.id)
          next
        end

        # open or initialize this repo
        local_path = File.join(@checkout_path, repo_instances.name, id)

        puts "Updating repo / instance "+repo.name+" / "+repo.id+" from uri: "+repo.uri+" into path: "+local_path

        # make sure there's an actual uri
        unless repo.uri
          raise IndexException.new("No URI for repo instance " + id, id)
        end

        if @domain_blacklist.include? URI(repo.uri).hostname
          msg = "Repo instance " + id + " has a blacklisted hostname: " + repo.uri.to_s
          puts ('WARNING:' + msg).yellow
          repo.errors << msg
          next
        end

        (1..3).each do |attempt|
          begin
            # open or create a repo
            vcs = get_vcs(repo)
            unless (not vcs.nil? and vcs.valid?) then next end

            # fetch the repo
            begin
              vcs.fetch()
            rescue VCSException => e
              msg = "Could not update repo, using old version: "+e.msg
              puts ("WARNING: "+msg).yellow
              repo.errors << msg
              vcs.close()
            end
            # too many open files if we don't do this
            vcs.close()

            break
          rescue VCSException => e
            puts ("Failed to communicate with source repo after #{attempt} attempt(s)").yellow
            if attempt == 3
              raise IndexException.new("Could not fetch source repo: "+e.msg, id)
            end
          end
        end

      rescue IndexException => e
        @errors[repo_instances.name] << e
        repo.accessible = false
        repo.errors << e.msg
      end

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


  def extract_package(site, distro, repo, snapshot, checkout_path, path, pkg_type, manifest_xml)

    data = snapshot.data

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
        # check for a stack.xml file
        stack_xml_path = File.join(path,'stack.xml')
        if File.exist?(stack_xml_path)
          stack_xml = IO.read(stack_xml_path)
          stack_doc = REXML::Document.new(stack_xml)
          package_name = REXML::XPath.first(stack_doc, "/stack/name/text()").to_s.strip
          if package_name.length == 0
            package_name = File.basename(File.join(path)).strip
          end
          version = REXML::XPath.first(stack_doc, "/stack/version/text()").to_s.strip
        else
          package_name = File.basename(File.join(path)).strip
          version = "UNKNOWN"
        end

        # read the package manifest
        manifest_doc = REXML::Document.new(manifest_xml)

        # get dependencies
        pkg_deps = Hash[*REXML::XPath.each(manifest_doc, "/package/depend/@package").map { |a| a.to_s.strip }.uniq.collect {|d| [d, nil]}.flatten]
        system_deps = Hash[*REXML::XPath.each(manifest_doc, "/package/rosdep/@name").map { |a| a.to_s.strip }.uniq.collect {|d| [d, nil]}.flatten]
      else
        return nil
      end

      dputs " ---- Found #{pkg_type} package \"#{package_name}\" in path #{path}"

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

      # extract rosindex exports
      tags = REXML::XPath.each(manifest_doc, "/package/export/rosindex/tags/tag/text()").map { |t| t.to_s }
      nodes = REXML::XPath.each(manifest_doc, "/package/export/rosindex/nodes").map { |nodes|
        case nodes.attributes["format"]
        when "hdf"
          get_hdf(nodes.text)
        else
          REXML::XPath.each(manifest_doc, "/package/export/rosindex/nodes/node").map { |node|
            {
              'name' => REXML::XPath.first(node,'/name/text()').to_s,
              'description' => REXML::XPath.first(node,'/description/text()').to_s,
              'ros_api' => get_ros_api(REXML::XPath.first(node,'/description/api'))
            }
          }
        end
      }

      # compute the relative path from the root of the repo to this directory
      package_relpath = Pathname.new(File.join(*path)).relative_path_from(Pathname.new(checkout_path))

      local_package_path = Pathname.new(path)

      # extract package manifest info
      raw_uri = File.join(data['raw_uri'], package_relpath)
      browse_uri = File.join(data['browse_uri'], package_relpath)

      # extract the paths to the readme files that were explicitly declared in the package
      readmes_relpath = REXML::XPath.each(manifest_doc, "/package/export/rosindex/readme/text()").map(&:to_s)

      # load the package's readme for this branch if it exists
      readme_file = Dir.glob(File.join(path, "README*"), File::FNM_CASEFOLD)
      unless readme_file.empty? then
        readmes_relpath.push(File.basename(readme_file.first))
      end

      # Iterate over each of the readme file paths that were explicitly declared in package
      readmes = Array.new
      readmes_relpath.each do |readme_relpath|
        tmp_readme_rendered, tmp_readme  = get_md_rst_txt(site, path, readme_relpath, raw_uri, browse_uri)
        readme = {
          'browse_uri' => File.join(browse_uri, readme_relpath),
          'readme' => tmp_readme,
          'readme_rendered' => tmp_readme_rendered
        }
        if package_relpath.to_s. == "." then
          readme['relpath'] = readme_relpath
        else
          readme['relpath'] = File.join(package_relpath, readme_relpath)
        end
        readmes.push(readme)
      end
      readmes.reject! do |x|
        x['readme'].nil? || x['readme_rendered'].nil?
      end

      # check for changelog in same directory as package.xml
      changelog_rendered, changelog = get_changelog(site, path, raw_uri, browse_uri)

      # TODO: don't do this for cmake-based packages
      # look for launchfiles in this package
      launch_files = Dir[File.join(path,'**','*.launch')]
      launch_files += Dir[File.join(path,'**','*.xml')].reject do |f|
        begin
          REXML::Document.new(IO.read(f)).root.name != 'launch'
        rescue Exception => e
          true
        end
      end
      # look for message files in this package
      msg_files = Dir[File.join(path,'**','*.msg')]
      # look for service files in this package
      srv_files = Dir[File.join(path,'**','*.srv')]
      # look for plugin descriptions in this package
      plugin_data = REXML::XPath.each(manifest_doc, '//export/*[@plugin]').map {|e| {'name'=>e.name, 'file'=>e.attributes['plugin'].sub('${prefix}','')}}


      launch_data = []
      launch_data = launch_files.map do |f|
        relative_path = Pathname.new(f).relative_path_from(local_package_path).to_s
        begin
          parse_launch_file(f, relative_path)
        rescue Exception => e
          @errors[repo.name] << IndexException.new("Failed to parse launchfile #{relative_path}: " + e.to_s)
        end
      end

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
        # rosindex metadata
        'tags' => tags,
        'nodes' => nodes,
        # readme
        'readmes' => readmes,
        # changelog
        'changelog' => changelog,
        'changelog_rendered' => changelog_rendered,
        # assets
        'launch_data' => launch_data,
        'plugin_data' => plugin_data,
        'msg_files' => msg_files.map {|f| Pathname.new(f).relative_path_from(local_package_path).to_s },
        'srv_files' => srv_files.map {|f| Pathname.new(f).relative_path_from(local_package_path).to_s },
      }

    rescue REXML::ParseException => e
      @errors[repo.name] << IndexException.new("Failed to parse package manifest: " + e.to_s)
      return nil
    end

    return package_info
  end

  def find_packages(site, distro, repo, snapshot, local_path)

    data = snapshot.data
    packages = {}

    # find packages in this branch
    Find.find(local_path) do |path|
      if FileTest.directory?(path)
        # skip certain paths
        if (File.basename(path)[0] == ?.) or File.exist?(File.join(path,'CATKIN_IGNORE')) or File.exist?(File.join(path,'AMENT_IGNORE')) or File.exist?(File.join(path,'.rosindex_ignore'))
          Find.prune
        end

        # check for package.xml in this directory
        package_xml_path = File.join(path,'package.xml')
        manifest_xml_path = File.join(path,'manifest.xml')
        stack_xml_path = File.join(path,'stack.xml')

        if File.exist?(package_xml_path)
          manifest_xml = IO.read(package_xml_path)
          pkg_type = 'catkin'
        elsif File.exist?(manifest_xml_path)
          manifest_xml = IO.read(manifest_xml_path)
          pkg_type = 'rosbuild'
        else
          next
        end

        # Try to extract a package from this path
        package_info = extract_package(site, distro, repo, snapshot, local_path, path, pkg_type, manifest_xml)

        unless package_info.nil?
          packages[package_info['name']] = package_info
          dputs " -- added package " << package_info['name']

          # stop searching a directory after finding a package
          Find.prune
        end
      end
    end

    return packages
  end

  # scrape a version of a repository for packages and their contents
  def scrape_version(site, repo, distro, snapshot, vcs)

    unless repo.uri
      puts ("WARNING: no URI for "+repo.name+" "+repo.id+" "+distro).yellow
      return
    end

    # initialize this snapshot data
    data = snapshot.data = {
      # get the uri for resolving raw links (for imgages, etc)
      'raw_uri' => get_raw_uri(repo.uri, repo.type, snapshot.version),
      'browse_uri' => get_browse_uri(repo.uri, repo.type, snapshot.version),
      # get the date of the last modification
      'last_commit_time' => vcs.get_last_commit_time(),
      'readme' => nil,
      'readme_rendered' => nil,
      'contributing_rendered' => nil}

    # load the repo readme for this branch if it exists
    data['readme_rendered'], data['readme'] = get_readme(
      site, vcs.local_path, data['raw_uri'], data['browse_uri'])

    # load the repo CONTRIBUTING.md for this branch if it exists
    data['contributing_rendered'] = get_contributing(
      site, vcs.local_path, data['raw_uri'], data['browse_uri'])

    unless repo.release_manifests[distro].nil?
      package_info = extract_package(site, distro, repo, snapshot, vcs.local_path, vcs.local_path, 'catkin', repo.release_manifests[distro])
      packages = {package_info['name'] => package_info}
    else
      packages = find_packages(site, distro, repo, snapshot, vcs.local_path)
    end

    # get all packages from the repo
    # TODO: check if the repo has a release manifest for this distro, and in
    # that case, use that file for package info
    # TODO: split `find_packages` out into two functions:
    #   find_packages (get a list of all package paths in this repo)
    #   scrape_package (extract info from this package) (maybe just move this into the loop below)

    # add the discovered packages to the index
    packages.each do |package_name, package_data|
      # create a new package snapshot
      package = PackageSnapshot.new(package_name, repo, snapshot, package_data)

      # store this package in the repo snapshot
      snapshot.packages[package_name] = package

      # collect tags from discovered packages
      repo.tags = Set.new(repo.tags).merge(package_data['tags']).to_a

      # add this package to the global package dict
      @package_names[package_name].instances[repo.id] = repo
      @package_names[package_name].tags = Set.new(@package_names[package_name].tags).merge(package_data['tags']).to_a

      # add this package as the default for this distro
      if @repo_names[repo.name].default
        dputs " --- Setting repo instance " << repo.id << "as default for package " << package_name << " in distro " << distro
        @package_names[package_name].repos[distro] = repo
        @package_names[package_name].snapshots[distro] =  package
      end
    end
  end

  def scrape_repo(site, repo)

    if @domain_blacklist.include? URI(repo.uri).hostname
      msg = "Repo instance " + repo.id + " has a blacklisted hostname: " + repo.uri.to_s
      puts ('WARNING:' + msg).yellow
      repo.errors << msg
      return
    end

    # open or initialize this repo
    begin
      vcs = get_vcs(repo)
    rescue VCSException => e
      raise IndexException.new(e.msg, repo.id)
    end
    if (vcs.nil? or not vcs.valid?) then return end

    some_version_found = false

    # get versions suitable for checkout for each distro
    repo.snapshots.each do |distro, snapshot|

      # get explicit version (this is either set or nil)
      explicit_version = snapshot.version

      if explicit_version.nil?
        dputs " -- no explicit version for distro " << distro << " looking for implicit version "
      else
        dputs " -- looking for version " << explicit_version.to_s << " for distro " << distro
      end

      begin
        # get the version
        unless explicit_version.nil?
          dputs (" Looking for explicit version #{explicit_version}").green
        end
        version, snapshot.version = vcs.get_version(explicit_version)

        # scrape the data (packages etc)
        if version
          puts (" --- scraping version for " << repo.name << " instance: " << repo.id << " distro: " << distro).blue

          # check out this branch
          vcs.checkout(version)

          # check for ignore file
          if File.exist?(File.join(vcs.local_path,'.rosindex_ignore'))
            puts (" --- ignoring version for " << repo.name).yellow
            snapshot.version = nil
          else
            some_version_found = true
            scrape_version(site, repo, distro, snapshot, vcs)
          end
        else
          dputs (" --- no version for " << repo.name << " instance: " << repo.id << " distro: " << distro).yellow
        end
      rescue VCSException => e
        @errors[repo.name] << IndexException.new("Could not find version for distro #{distro}: "+e.msg, repo.id)
        repo.errors << e.msg
      end
    end

    if not some_version_found
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

    # create the checkout path if necessary
    @checkout_path = File.expand_path(site.config['checkout_path'])
    puts ("Using checkout path: " + @checkout_path).green
    unless File.exist?(@checkout_path)
      FileUtils.mkpath(@checkout_path)
    end

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

    @skip_update = site.config['skip_update']
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
    rosdep_path = site.config.key?('rosdep_path') ? site.config['rosdep_path']: site.config['rosdistro_paths'].first

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
          platform_details['versions'].each do |version_key, version_name|
            platform_data[platform_key][version_key] = resolve_dep(platforms, manager_set, platform_key, version_key, dep_data)
          end
          # Get dep description from debian
          if platform_key == 'debian' and platform_data[platform_key].has_key?('bullseye')
            platform_data[platform_key]['bullseye'].each do |debian_key|
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
          platform_data[platform_key] = resolve_dep(platforms, manager_set, platform_key, 'any_version', dep_data)
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
      puts ("Using discovery to find repos").green
      repos, discovery_errors = discover_repos(site.config, DISCOVERY_RESULTS, DISCOVERY_ERRORS)
    end
    discovery_errors.each do |distro, vals|
      vals.each { |val| @errors[distro].push(IndexException.new(val["msg"], val["repo_id"])) }
    end

    # Create repo objects
    repos.each do |distro, repo_list|
      puts ("creating repo objects for rosdistro: "+distro).green
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
            'Via rosdistro: '+distro,
            @checkout_path)
        rescue
            raise IndexException.new("Failed to create repo from #{repo_item['type']} repo #{repo_item['uri']}: " + repo_item['name'])
        end

        # create a new repo structure for this remote
        if @all_repos.key?(repo.id)
          repo = @all_repos[repo.id]
        else
          puts " -- Adding repo " << repo.name << " instance: " << repo.id << " from uri: " << repo.uri.to_s << " with version: " << repo_item['version']
          # store this repo in the unique index
          @all_repos[repo.id] = repo
        end

        # get maintainer status
        repo.status = repo_item['status']
        
        # add the specific version from this instance
        repo.snapshots[distro] = RepoSnapshot.new(repo_item['version'], distro, repo_item['release'], true)

        # add the release manifest, if found
        repo.release_manifests[distro] = repo_item['manifest']

        # store this repo in the name index
        @repo_names[repo.name].instances[repo.id] = repo
        @repo_names[repo.name].default = repo
      rescue IndexException => e
        @errors[repo_item['name']] << e
      end
    end

    puts "Found " << @all_repos.length.to_s << " repositories corresponding to " << @repo_names.length.to_s << " repo identifiers."

    # clone / fetch all the repos
    unless @skip_update
      work_q = Queue.new
      @repo_names.sort.map.each {|r| work_q.push r}
      puts "Fetching sources with " << site.config['checkout_threads'].to_s << " threads."
      workers = (0...site.config['checkout_threads']).map do
        Thread.new do
          begin
            while ri = work_q.pop(true)
              update_local(site, ri[1])
            end
          rescue ThreadError
          end
        end
      end; "ok"
      workers.map(&:join); "ok"
    end

    # scrape all the repos
    unless @skip_scrape
      n_scraped = 0
      n_total = @all_repos.length
      puts "Scraping #{n_total} known repos..."
      @all_repos.to_a.sort_by{|repo_id, repo| repo.name}.each do |repo_id, repo|
        unless (site.config['repo_name_whitelist'].length == 0 or site.config['repo_name_whitelist'].include?(repo.name)) then next end
        if site.config['repo_id_whitelist'].size == 0 or site.config['repo_id_whitelist'].include?(repo.id)

          puts "[%05.2f%%] Scraping #{repo.id}..." % (n_scraped/n_total.to_f*100.0)
          begin
            scrape_repo(site, repo)
          rescue IndexException => e
            @errors[repo.name] << e
            repo.errors << e.msg
          end
          n_scraped = n_scraped + 1
        end
      end
    end

    if site.config['use_db_cache']
      # backup the current db if it exists
      if File.exist?(@db_cache_filename) then FileUtils.mv(@db_cache_filename, @db_cache_filename+'.bak') end
      # save scraped data into the cache db
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

      # create a list of instances for this repo
      site.pages << RepoInstancesPage.new(site, repo_instances)

      # create the page for the default instance
      site.pages << RepoPage.new(site, repo_instances, repo_instances.default, true)

      # create pages for each repo instance
      repo_instances.instances.each do |instance_id, instance|
        site.pages << RepoPage.new(site, repo_instances, instance, false)
      end
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

    @rosdeps.each do |dep_name, full_dep_data|
      site.pages << DepPage.new(site, dep_name, raw_rosdeps[dep_name], full_dep_data)
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
              'tags' => (p['tags'] + package_name.split('_')) * " ",
              'package' => package_name,
              'repo' => repo.name,
              'core' => core,
              'released' => if repo_snapshot.released then 'released' else '' end,
              'version' => p['version'],
              'description' => p['description'].strip,
              'maintainers' => p['maintainers'] * ", ",
              'authors' => p['authors'] * ", ",
              'distro' => distro,
              'instance' => repo.name + '/' + repo.id,
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
                names_for_version.collect do |name|
                  aliases.add(name)
                  "#{name} (#{platform_name} #{version_name})"
                end.join(' : ')
              end.compact.join(' : ')
            else
              data.collect do |name|
                aliases.add(name)
                "#{name} (#{platform_name})"
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
