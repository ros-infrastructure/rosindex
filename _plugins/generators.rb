
# http://www.rubydoc.info/github/mojombo/jekyll/Jekyll
#
require 'git'
require 'fileutils'

def github_uri(ns,repo)
  return 'https://github.com/%s/%s.git' % [ns,repo]
end

def make_remote_name(type, ns, repo)
  return [type, ns, repo].join("/")
end

class RepoVariant 
  attr_accessor :repo, :branch, :distro, :readme, :readme_rendered
  def initialize(site, repo, branch, distro)
    @site = site

    @repo = repo
    @branch = branch
    @distro = distro
    @readme = '*No README.md file found. Maybe try [wiki.ros.org](http://www.ros.org/browse/list.php)*'
    @readme_rendered = ''
  end

  def render_readme
    mkconverter = @site.getConverterImpl(Jekyll::Converters::Markdown)
    @readme_rendered = mkconverter.convert(@readme)
    return @readme_rendered
  end

  def to_liquid(attrs = Jekyll::Post::ATTRIBUTES_FOR_LIQUID)
    return {
      'readme_rendered' => @readme_rendered
    }
  end
end

class PackageVariant
  def initialize(repo, branch, distro)
    @repo = repo
    @branch = branch
    @distro = distro
    @readme = ''
    @manifest = ''
  end
end

class GitScraper < Jekyll::Generator
  def generate(site)
    print("site: "+site.inspect+"\n")
    print("cwd: " + Dir.getwd + "\n")
    checkout_path = site.config['checkout_path']
    print("checkout path: " + checkout_path + "\n")
    unless File.exist?(checkout_path)
      FileUtils.mkpath(checkout_path)
    end

    all_distros = site.config['distros'] + site.config['old_distros']

    # get the collection of repos
    repos = site.collections['repos']

    # update and extract data from each repo
    repos.docs.each do |repo|
      # create or open the repo
      g = nil
      local_path = File.join(checkout_path, repo.data['name'])
      unless File.exist?(local_path)
        # initialize a new local repo
        print("initializing local repo: " + repo.data['name']+"\n")
        g = Git.init(local_path)
      else
        print("opening existing local repo: " + repo.data['name']+"\n")
        # open existing local repo
        g = Git.open(local_path)
      end
      
      # get branches corresponding to ros distros
      distro_variants = Hash.new {|h,k| h[k]=[]}

      # fetch all the instances
      repo.data['instances'].each do |instance|
        # create page for this repo
        # TODO: deal with non-github types
        uri = github_uri(instance['ns'], instance['name'])

        # find the remote if it already exists
        remote = nil
        g.remotes.each do |r|
          if r.url == uri
            remote = r
          end
        end

        # add the remote if it isn't found
        if remote.nil?
          remote_name = make_remote_name(instance['type'], instance['ns'], instance['name'])
          print("adding remote "+remote_name+" from: " + uri + "\n")
          remote = g.add_remote(remote_name, uri)
        end

        # fetch the remote
        print("fetching remote "+remote.inspect+" from: " + remote.url + "\n")
        g.fetch(remote)
      end

      g.branches.each do |branch|
        branch_tail = branch.to_s.split('/')[-1]
        print(" - branch: " + branch.inspect + " "+branch_tail+"\n")

        # get all branches for this distro (which aren't detached branches)
        # TODO: handle detached branches more cleanly
        all_distros.each do |distro|
          if branch_tail.include? distro and not branch.to_s.include? 'detached'
            # store a new variant
            distro_variants[distro] << RepoVariant.new(site, repo, branch, distro)
          end
        end
      end
      print("distro branches: " + distro_variants.inspect + "\n")

      # get README.md files from each distro (and forks)
      readmes = Hash.new()
      all_distros.each do |distro|
        variants = distro_variants[distro]
        variants.each do |variant|
          print("checking out "+variant.branch.name+"\n")
          g.checkout(variant.branch)
          readme_path = File.join(local_path,'README.md')

          # load the readme if it exists
          if File.exist?(readme_path)
            print("distro "+distro+" has readme\n")
            variant.readme = IO.read(readme_path)
          end

          # render the readme
          variant.render_readme
        end
      end

      site.pages << RepoPage.new( site, site.source, File.join('r', repo.data['name']), distro_variants)
    end
  end
end

class RepoPage < Jekyll::Page
  def initialize(site, base, dir, distro_variants)
    @site = site
    @base = base
    @dir = dir
    @name = 'index.html'

    self.process(@name)
    self.read_yaml(File.join(base, '_layouts'),'repo.html')
    # clone (or update) git repo
    # for each ROSDISTRO-devel branch
    # list all ROS packages in the repo
    #site.pages << PackagePage.new(...)
    self.data['distro_variants'] = distro_variants
  end
end

class PackagePage < Jekyll::Page
  def initialize(site, base, dir, name)
    super(site, base, dir, name)
  end
end
