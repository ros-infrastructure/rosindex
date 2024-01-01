
require_relative 'common'

class PackageSnapshot < Liquid::Drop
  # This represents a snapshot of a ROS package found in a repo snapshot
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

class RepoSnapshot < Liquid::Drop
  # This represents a snapshot of a version control repository
  attr_accessor :released, :documented, :distro, :version, :data, :packages
  def initialize(version, distro, released, documented)
    # the version control system version string
    # this is either a branch or tag of the remote repo
    @version = version

    # whether this snapshot is released
    @released = released

    # whether this snapshot has generated api docs
    @documented = documented

    # the distro that this snapshot works with
    @distro = distro

    # metadata about this snapshot
    @data = {}

    # package name -> PackageSnapshot
    # these are all the packages in this repo snapshot
    @packages = {}
  end
end

class Repo < Liquid::Drop
  # This represents a remote repository
  attr_accessor :name, :id, :uri, :accessible, :errors, :purpose, :snapshots, :tags, :type, :status, :local_path, :local_name, :release_manifests
  def initialize(name, type, uri, purpose, checkout_path, id = nil)
    # non-unique identifier for this repo
    @name = name

    # the uri for cloning this repo
    @uri = cleanup_uri(uri)

    # unique identifier
    @id = if id then id else get_id(@uri) end

    # the version control system type
    @type = type

    # a brief description of this remote
    @purpose = purpose

    # maintainer status
    @status = nil

    # whether it's accesible or not
    @accessible = true

    # a list of error messages
    @errors = []

    # the local repo name to checkout to (this is important for older rosbuild packages)
    @local_name = name

    # the local path to this repo
    @local_path = File.join(checkout_path, @name, @id, @local_name)

    # hash distro -> RepoSnapshot
    # each entry in this hash represents the preferred version for a given distro in this repo
    @snapshots = Hash[$all_distros.collect { |d| [d, RepoSnapshot.new(nil, d, false, false)] }]

    # tags from all versions
    @tags = []

    # release manifests
    # hash distro -> manifest xml data
    @release_manifests = {}
  end
end

class RepoInstances < Liquid::Drop
  # This represents a group of repositories with the same name
  attr_accessor :name, :default, :instances
  def initialize(name)
    # identifier for this repo
    @name = name

    # hash instance_id -> Repo
    # these are all of the known instances of this repo
    @instances = {}

    # reference to the preferred Repo instance
    @default = nil
  end
end

class PackageInstances < Liquid::Drop
  # This represents a group of package snapshots with the same name
  attr_accessor :name, :tags, :instances, :snapshots, :repos
  def initialize(name)
    # name of the package
    @name = name

    # tags from all package instances
    @tags = []

    # hash distro -> RepoSnapshot
    # each entry in this hash is the preferred snapshot for this package
    @repos = Hash[$all_distros.collect { |d| [d, nil] }]
    @snapshots = Hash[$all_distros.collect { |d| [d, nil] }]

    # hash instance_id -> Repo
    # each repo in this hash contains the package in question, even if it's not a preferred snapshot
    @instances = {}
  end
end

class RosIndexDB
  attr_accessor :rosdeps, :all_repos, :repo_names, :package_names, :errors
  def initialize
    # the rosdep db
    @rosdeps = Hash.new
    # the global index of repos
    @all_repos = Hash.new
    # the list of repo instances by name
    @repo_names = Hash.new
    # the list of package instances by name
    @package_names = Hash.new
    # the errors encountered while processing
    @errors = Hash.new

    self.add_procs
  end

  def get_report
    report = {
      'rosdeps'=>@rosdeps,
      'repos'=>{},
      'repo_instances'=>{},
      'packages'=>{}
    }

    @repo_names.each do |repo_name, details|
      report['repos'][repo_name] = {
        'instances' => details.instances.keys
      }

      details.instances.each do |instance_id, repo|
        instance_report = {
          'uri' => repo.uri,
          'type' => repo.type,
          'local_name' => repo.local_name,
          'versions' => Hash[repo.snapshots.map{|distro, snapshot| [distro, snapshot.version.to_s]}]
        }

        report['repo_instances'][instance_id] = instance_report
      end
    end

    @package_names.each do |package_name, package_instances|
      report['packages'][package_name] = package_instances.instances.keys
    end

    return report
  end

  def diff_report(old_report, new_report)
    return {
      'adds' => report_adds(old_report, new_report),
      'dels' => report_adds(new_report, old_report),
      'mods' => report_mods(old_report, new_report)
    }
  end

  def report_adds(from_report, to_report)
    adds = {}
    from_report.each do |category, data|
      adds[category] = []
      to_report[category].each do |k,v|
        if not from_report[category].key?(k)
          adds[category] << k
        end
      end
    end

    return adds
  end

  def report_mods(from_report, to_report)
    mods = {}
    from_report.each do |category, data|
      mods[category] = []
      to_report[category].each do |k,v|
        if from_report[category].key?(k) and from_report[category][k] != to_report[category][k]
          mods[category] << k
        end
      end
    end

    return mods
  end

  def add_procs
    @repo_names.default_proc = proc do |h, k|
      h[k]=RepoInstances.new(k)
    end

    @package_names.default_proc = proc do |h, k|
      h[k]=PackageInstances.new(k)
    end

    @errors.default_proc = proc do |h,k|
      h[k]=[]
    end
  end

  def marshal_dump
    [Hash[@rosdeps], Hash[@all_repos], Hash[@repo_names], Hash[@package_names], Hash[@errors]]
  end

  def marshal_load array
    @rosdeps, @all_repos, @repo_names, @package_names, @errors = array
    self.add_procs
  end
end

def get_vcs(repo)

  vcs = nil

  case repo.type
  when 'git'
    dputs "Getting git repo: " + repo.uri.to_s
    vcs = GIT.new(repo.local_path, repo.uri)
  when 'hg'
    dputs "Getting hg repo: " + repo.uri.to_s
    vcs = HG.new(repo.local_path, repo.uri)
  when 'svn'
    dputs "Getting svn repo: " + repo.uri.to_s
    vcs = GITSVN.new(repo.local_path, repo.uri)
  else
    raise IndexException.new("Unsupported VCS type: "+repo.type.to_s, repo.id)
  end

  if vcs.valid?
    return vcs
  else
    return nil
  end
end

