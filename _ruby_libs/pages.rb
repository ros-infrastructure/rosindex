# Jekyll page classes

require 'cgi'

def get_available_distros(site, versions_dict)
  # create easy-to-process lists of available distros for the switcher

  available_distros = {}
  available_older_distros = {}

  site.config['distros'].each do |distro|
    available_distros[distro] = (versions_dict[distro] != nil and versions_dict[distro].version != nil)
  end

  site.config['old_distros'].each do |distro|
    available_older_distros[distro] = (versions_dict[distro] != nil and versions_dict[distro].version != nil)
  end

  return available_distros, available_older_distros, available_older_distros.values.count(true)
end

class DepPage < Jekyll::Page
  def initialize(site, dep_name, dep_data, full_dep_data)

    basepath = File.join('d', dep_name)

    @site = site
    @base = site.source
    @dir = basepath
    @name = 'index.html'

    self.process(@name)
    self.read_yaml(File.join(@base, '_layouts'),'dep.html')

    self.data['dep_name'] = dep_name
    self.data['dep_data'] = dep_data
    self.data['title'] = 'rosdep System Dependency: ' + dep_name

    self.data['dep_data_per_platform'] = full_dep_data['data_per_platform']
    self.data['dependants_per_distro'] = full_dep_data['dependants_per_distro']
    self.data['description'] = full_dep_data['description']
  end
end


class RepoPage < Jekyll::Page
  def initialize(site, instances)

    basepath = File.join('r', instances.name)

    @site = site
    @base = site.source
    @dir = basepath
    @name = 'index.html'

    self.process(@name)
    self.read_yaml(File.join(@base, '_layouts'),'repo_instance.html')

    self.data['redirect_from'] = [ File.join('repos', instances.name) + '/']
    instances.instances.each do |id, repo_inst|
      self.data['redirect_from'] << File.join('r', repo_inst.name, id) + '/'
    end

    self.data['instances'] = instances

    # Use the same logic for repo selection as packages.
    # This could likely be collected earlier in a simpler format.
    all_snapshots = {}
    instances.instances.each do |id, repo|
      all_snapshots = all_snapshots.merge(repo.snapshots)
    end

    self.data['available_distros'],
    self.data['available_older_distros'],
    self.data['n_available_older_distros'] = get_available_distros(site, all_snapshots)
    self.data['all_distros'] = site.config['distros'] + site.config['old_distros']

    self.data['default_distro'] = self.data['available_distros'].keys.first or
                                  self.data['available_older_distros'].keys.first or
                                  self.data['all_distros'].first
  end
end

class HomePage < Jekyll::Page
  def initialize(site)
    @site = site
    @base = site.source
    @dir = '/'
    @name = 'index.html'

    self.process(@name)
    self.read_yaml(File.join(@base, '_layouts'),'search_packages.html')

    self.data['title'] = 'ROS Index'
    self.data['all_distros'] = site.config['distros'] + site.config['old_distros']
    self.data['available_distros'] = Hash[site.config['distros'].collect { |d| [d, true] }]
    self.data['available_older_distros'] = Hash[site.config['old_distros'].collect { |d| [d, true] }]
    self.data['n_available_older_distros'] = site.config['old_distros'].length
  end
end

class SearchDepsListPage < Jekyll::Page
  def initialize(site)
    @site = site
    @base = site.source
    @dir = 'search_deps/'
    @name = 'index.html'

    self.process(@name)
    self.read_yaml(File.join(@base, '_layouts'),'search_deps.html')
    self.data['title'] = 'System Dependencies'
  end
end


class PackagePage < Jekyll::Page
  def initialize(site, package_instances)
    @site = site
    @base = site.source
    @dir = File.join('p',package_instances.name)
    @name = 'index.html'

    self.process(@name)
    self.read_yaml(File.join(@base, '_layouts'),'package.html')
    self.data['package_instances'] = package_instances

    # Redirect from retired urls in #483
    self.data['redirect_from'] = []
    package_instances.instances.each_key do |instance_id|
      self.data['redirect_from'].append(File.join('p', package_instances.name, instance_id) + '/')
    end

    self.data['package_name'] = package_instances.name
    self.data['title'] = 'ROS Package: ' + package_instances.name

    self.data['instances'] = package_instances.instances

    self.data['redirect_from'] = [ File.join('packages',package_instances.name) + '/']

    self.data['available_distros'],
    self.data['available_older_distros'],
    self.data['n_available_older_distros'] = get_available_distros(site, package_instances.snapshots)
    self.data['all_distros'] = site.config['distros'] + site.config['old_distros']

    self.data['default_distro'] = self.data['available_distros'].keys.first or
                                  self.data['available_older_distros'].keys.first or
                                  self.data['all_distros'].first
  end
end


class StatsPage < Jekyll::Page
  def initialize(site, package_names, all_repos, errors)

    @site = site
    @base = site.source
    @dir = 'stats'
    @name = 'index.html'

    self.process(@name)
    self.read_yaml(File.join(@base, '_layouts'),'stats.html')

    self.data['n_packages'] = package_names.length
    self.data['n_repos'] = all_repos.length
    self.data['n_errors'] = errors.length

    # compute venn diagram model
    distro_counts = Hash[$recent_distros.collect { |d| [d, 0] }]
    distro_overlaps = Hash[(2..$recent_distros.length).flat_map{|n| $recent_distros.combination(n).to_a}.collect { |s| [s.sort, 0] }]
    puts 'distro_overlaps: ' + distro_overlaps.to_s

    package_names.each do |package_name, package_instances|
      overlap = []
      #package_instances.snapshots.reject.with_index{|dr, i| dr[1].nil? || dr[1].version.nil? }
      package_instances.snapshots.each do |distro, s|
        if not s.nil? and not s.version.nil? and not distro_counts[distro].nil?
          overlap << distro
          distro_counts[distro] += 1
        end
      end
      overlap = overlap.sort

      puts package_name.to_s + " " + overlap.to_s

      package_overlaps = (2..$recent_distros.length).flat_map{|n| overlap.combination(n).to_a}

      package_overlaps.each do |o|
        distro_overlaps[o] = distro_overlaps[o] + 1
      end
    end

    self.data['distro_counts'] = distro_counts
    self.data['distro_overlaps'] = Hash[distro_overlaps.collect{|s,c| [s.inspect, c]}]

    # generate date-histogram data
    self.data['distro_activity'] = {}
    now = DateTime.now
    $all_distros.each do |distro|
      activity = []
      all_repos.each do |id, repo|
        if repo.snapshots[distro].nil? or repo.snapshots[distro].data['last_commit_time'].nil? then next end
        activity << (now - DateTime.parse(repo.snapshots[distro].data['last_commit_time'])).to_f
      end
      self.data['distro_activity'][distro] = activity
    end
  end
end

class SearchIndexFile < Jekyll::StaticFile
  # Override write as the search.json index file has already been created
  def write(dest)
    true
  end
end
class PackageManifestFile < Jekyll::StaticFile
  def write(dest)
    true
  end
end

class ReportFile < Jekyll::StaticFile
  def write(dest)
    true
  end
end

class ErrorsPage < Jekyll::Page
  def initialize(site, errors)
    @site = site
    @base = site.source
    @dir = File.join('stats','errors')
    @name = 'index.html'

    self.process(@name)
    self.read_yaml(File.join(@base, '_layouts'),'errors.html')
    self.data['errors'] = []

    errors.each do |name, repo_errors|
      repo_errors.each do |error|
        error_hash = error.to_hash.merge({'name'=>name})
        error_hash['msg'] = CGI.escapeHTML(error_hash['msg'])

        self.data['errors'] << error_hash
      end
    end

    self.data['errors'].sort_by! {|e| e['name']}
  end
end
