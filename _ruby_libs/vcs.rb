# Version control systems

require 'colorator'
require 'uri'
require 'typhoeus'
require 'open3'

#require 'git'
require 'rugged'
require 'mercurial-ruby'

# rosindex requires
require_relative 'common'

Mercurial.configure do |conf|
  conf.hg_binary_path = `which hg`.rstrip
end

class VCSException < RuntimeError
  attr :msg
  def initialize(msg)
    @msg = msg
    puts ("ERROR: #{@msg}").red
  end
end

class VCS
  # This represents a working copy of a remote repository
  # superlight abstract vcs wrapper
  #
  # features:
  #   - update from remote
  #   - list branches
  #   - list tags
  #   - checkout specific branch / tag
  #   - get latest commit date

  attr_accessor :local_path, :uri, :type
  def initialize(local_path, uri, type)
    @local_path = local_path
    @uri = uri
    @type = type
  end

  def check_uri()
    # make sure it is defined
    if @uri.nil? then return false end

    # make sure the uri actually exists
    resp = Typhoeus.get(@uri, followlocation: true, nosignal: true, connecttimeout: 3.0, ssl_verifypeer: false)
    if resp.code >= 400
      raise VCSException.new("Code "+resp.code.to_s+" bad URI: " + @uri)
    elsif resp.timed_out?
      raise VCSException.new("Timed out URI: " + @uri)
    elsif resp.success?
      return true
    end

    raise VCSException.new("Bad URI: " + @uri)
  end

  def hash
    return [local_path].hash
  end

  def eql?(other)
    return other.local_path == @local_path
  end

  def close
    return nil
  end

end

class GIT < VCS
  def initialize(local_path, uri)
    super(local_path, uri, 'git')

    @r = nil
    @origin = nil

    if File.exist?(@local_path)
      @r = Rugged::Repository.new(@local_path)
      dputs " - opened git repository at: " << @local_path << " from uri: " << @uri
    else
      @r = Rugged::Repository.init_at(@local_path)
      dputs " - initialized new git repository at: " << @local_path << " from uri: " << @uri
    end

    @origin = @r.remotes['origin']

    if @origin.nil?

      # add remote
      dputs " - adding remote for " << @uri << " to " << @local_path
      test_origin = @r.remotes.create('origin', @uri)

      if not test_origin.check_connection(:fetch)
        raise VCSException.new("Could not fetch from git repository at uri: " + uri)
      end
      @origin = test_origin
    end
  end

  def close()
    return @r.close
  end

  def valid?()
    return (not @origin.nil?)
  end

  def fetch()
    # fetch the remote
    unless $fetched_uris.key?(@uri)
      if true or (File.mtime(File.join(@local_path,'.git')) < (Time.now() - (60*60*24)))
        begin
          dputs " - fetching remote from: " + @uri
          @r.fetch(@origin)
        rescue Exception => e
          raise VCSException.new("Could not fetch git repository from uri: " + @uri+": "+e.to_s)
        end
      else
        dputs " - not fetching remote "
      end
      # this is no longer useful now that repos are all independent on disk
      #$fetched_uris[@uri] = true
    end
  end

  def checkout(version)

    if version.nil? then return end

    begin
      dputs " --- checking out " << version.to_s << " from uri: " << @uri
      @r.checkout(version)
    rescue
      dputs " --- resetting hard to " << version.to_s
      @r.reset(version.name, :hard)
    end
  end

  def get_last_commit_time()
    return @r.last_commit.time.strftime('%F')
  end

  def get_version(explicit_version)

    # remote head
    if explicit_version == 'REMOTE_HEAD'
      sha = nil

      begin
        @r.branches.each() do |branch|
          if branch.remote.nil? then next end
          #puts branch.remote.ls.to_a.inspect
          branch.remote.ls.each do |remote_ref|
            #puts remote_ref.inspect
            if remote_ref[:local?] == false and remote_ref[:name] == 'HEAD'
              sha = remote_ref[:oid]
              break
            end
          end
        end

        unless sha.nil?
          @r.branches.each() do |branch|
            #puts "name: #{branch.name}"
            #puts "oid: #{branch.target.oid}"
            if branch.target.oid == sha
              branch_name = branch.name.split('/')[-1]
              #dputs "Using branch '#{branch_name}' ('#{branch.name}')"
              return branch, branch_name # remote_ref[:oid]
            end
          end
        end
      rescue
      end

      #if @r.branches['master']
        #return @r.branches['master'], 'master'
      #end

      raise VCSException.new('Could not determine REMOTE HEAD for git repository.')
    end

    # get the version if it's a branch
    @r.branches.each() do |branch|
      # ignore this special branch
      if branch.name == 'git-svn' then next end

      # get the branch shortname
      if explicit_version and explicit_version.split('/').size > 1
        branch_name = branch.name.split('/').drop(1).join("/")
      else
        branch_name = branch.name.split('/')[-1]
      end

      # detached branches are those checked out by the system but not given names
      if branch.name.include? 'detached' then next end
      if branch.remote_name != 'origin' then next end

      # NOTE: no longer need to check remote names #if branch.remote_name != repo.id then next end

      #dputs " -- examining branch " << branch.name << " trunc: " << branch_name << " from remote: " << branch.remote_name

      # save the branch as the version if it matches the explicit version
      if explicit_version && branch_name == explicit_version
        return branch, branch_name
      end
    end

    # get the version if it's a tag
    @r.tags.each do |tag|
      tag_name = tag.name

      # save the tag if it matches the explicit version
      if explicit_version && tag_name == explicit_version
        return tag, tag_name
      end
    end

    return nil, nil
  end
end

class HG < VCS
  def initialize(local_path, uri)
    super(local_path, uri, 'hg')

    @r = nil
    @origin = nil

    begin
      if File.exist?(@local_path) and File.exist?(File.join(@local_path,'.hg'))
        @r = Mercurial::Repository.open(@local_path)
        dputs " - opened hg repository at: " << @local_path << " from uri: " << @uri
      else
        self.check_uri

        @r = Mercurial::Repository.clone(@uri, @local_path, {})
        dputs " - initialized new hg repository at: " << @local_path << " from uri: " << @uri
      end
    rescue Exception => e
      raise VCSException.new("Could not reach hg repository at uri: " + uri + ": " + e.to_s)
    end
  end

  def valid?()
    return (not @r.nil?)
  end

  def fetch()
    # fetch the remote
    if self.valid?
      begin
        @r.pull()
      rescue Exception => e
        raise VCSException.new("Could not pull hg repository at uri: " + @uri +": "+e.to_s)
      end
    end
  end

  def checkout(version)
    if self.valid?
      dputs " --- checking out " << version.to_s << " uri: " << @uri
      @r.shell.hg(['update ?', version])
    else
    end
  end

  def get_last_commit_time()
    if self.valid?
      return @r.commits.tip.date.strftime('%F')
    else
      return nil
    end
  end

  def get_version(explicit_version)
    # get remote head
    if explicit_version == 'REMOTE_HEAD'
      return 'default', 'default'
    end

    # get the version if it's a branch
    @r.branches.each() do |branch|
      # get the branch shortname
      branch_name = branch.name

      # save the branch as the version if it matches the explicit version
      if explicit_version && branch_name == explicit_version
        return branch.name, branch_name
      end
    end

    # get the version if it's a tag
    @r.tags.all.each do |tag|
      tag_name = tag.name

      # save the tag if it matches the explicit version
      if explicit_version && tag_name == explicit_version
        return tag.name, tag_name
      end
    end

    return nil, nil
  end
end

class GITSVN < GIT
  # we hates the subversionses
  # so use git instead!
  # this uses git-svn to clone an svn repo
  def initialize(local_path, uri)
    @local_path = local_path
    @uri = uri
    @origin = nil

    unless File.exist?(File.join(local_path,'.git'))
      begin
        self.check_uri
      rescue VCSException => e
        raise VCSException.new("Could not reach svn repository at uri: " + uri + ": " +e.msg)
      end
      if system("git svn clone -rHEAD #{uri} #{local_path}")
        dputs " - initialized new git-svn repository at: " << local_path << " from uri: " << uri
      else
        raise VCSException.new("Could not git-clone svn repository from uri: " + uri)
      end
    end

    super(local_path, uri)
  end

  def get_version(explicit_version)
    if explicit_version == 'REMOTE_HEAD'
      return @r.branches['master'], 'master' # super(distro, explicit_version = 'master')
    else
      return nil, nil
    end
  end

  def fetch()
    Open3.popen3("git svn rebase", :chdir=>@local_path) { |i,o,e,t|
      i.close
      unless t.value.success?
        raise VCSException.new("Could not update svn repository from uri: "+@uri+": "+e.read.chomp)
      end
    }
  end
end

