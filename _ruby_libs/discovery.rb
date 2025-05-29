#!/usr/bin/env ruby

# Prepare a json file with discovered repos. Can be run as a standalone program, or called from ruby

require 'json'
require 'optparse'
require 'yaml'

require_relative '../_ruby_libs/common'
require_relative '../_ruby_libs/vcs'

DISCOVERY_RESULTS = "_artifacts/discovery.json"
DISCOVERY_ERRORS = "_artifacts/discovery_errors.json"
DEFAULT_CONFIG = ["_config.yml", "index.yml"]

def discover_repos(config, output_path, errors_path)
    all_distros = config['distros'] + config['old_distros']
    checkout_path = File.expand_path(config['checkout_path'])
    errors = Hash.new
    errors.default_proc = proc do |h,k|
      h[k]=[]
    end

    repos = Hash.new
    # read in rosdistro sources
    all_distros.reverse_each do |distro|
      repos[distro] = Array.new
      puts "processing discovery for rosdistro: "+distro
      config['rosdistro_paths'].each do |rosdistro_path|
        # read in the rosdistro distribution file
        rosdistro_filename = File.join(rosdistro_path,distro,'distribution.yaml')
        if File.exist?(rosdistro_filename)
          distro_data = YAML.load_file(rosdistro_filename)
          distro_data['repositories'].each do |repo_name, repo_data|
            begin
              source_uri = nil
              source_version = nil
              source_type = nil
              release_manifest_xml = nil
              release_version = nil

              # only index if it has a source repo
              if repo_data.has_key?('source')
                source_uri = repo_data['source']['url'].to_s
                source_type = repo_data['source']['type'].to_s
                source_version = repo_data['source']['version'].to_s
                source_version = (if repo_data['source'].key?('version') and repo_data['source']['version'] != 'HEAD' then repo_data['source']['version'].to_s else 'REMOTE_HEAD' end)
              elsif repo_data.has_key?('doc')
                source_uri = repo_data['doc']['url'].to_s
                source_type = repo_data['doc']['type'].to_s
                source_version = (if repo_data['doc'].key?('version') and repo_data['doc']['version'] != 'HEAD' then repo_data['doc']['version'].to_s else 'REMOTE_HEAD' end)
              elsif repo_data.has_key?('release')
                # NOTE: also, sometimes people use the release repo as the "doc" repo

                # get the release repo to get the upstream repo
                release_uri = cleanup_uri(repo_data['release']['url'].to_s)
                release_repo_path = File.join(checkout_path,'_release_repos',repo_name,get_id(release_uri))

                tracks_file = nil

                (1..3).each do |attempt|
                  begin
                    # clone the release repo
                    release_vcs = GIT.new(release_repo_path, release_uri)

                    begin
                      puts "release_repo_path #{release_repo_path} release_uri #{release_uri} release_vcs #{release_vcs}"
                      release_vcs.fetch()
                    rescue VCSException => e

                    end

                    # get the tracks file
                    ['master','bloom'].each do |branch_name|
                      branch, _ = release_vcs.get_version(branch_name)

                      if branch.nil? then next end

                      release_vcs.checkout(branch)

                      begin
                        # get the tracks file
                        tracks_file = YAML.load_file(File.join(release_repo_path,'tracks.yaml'))
                        # get package manifest files (if any)
                        release_manifest_path = Dir[File.join(release_repo_path,distro,'package.xml')].first
                        unless release_manifest_path.nil?
                          release_manifest_xml = IO.read(release_manifest_path)
                        end

                        unless tracks_file.nil? then break end
                      rescue
                        next
                      end
                    end

                    # too many open files if we don't do this
                    release_vcs.close()

                    break
                  rescue VCSException => e
                    puts ("Failed to communicate with release repo after #{attempt} attempt(s)").yellow
                    if attempt == 3
                      raise IndexException.new("Could not fetch release repo for repo: "+repo_name+": "+e.msg)
                    end
                  end
                end

                if tracks_file.nil?
                  raise IndexException.new("Could not find tracks.yaml file in release repo: " + repo_name + " in rosdistro file: " + rosdistro_filename)
                end

                tracks_file['tracks'].each do |track_name, track|
                  if track['ros_distro'] == distro
                    source_uri = track['vcs_uri']
                    source_type = track['vcs_type']
                    # prefer devel branch if available
                    if not track['devel_branch'].nil?
                      source_version = track['devel_branch'].strip
                    elsif not track['release_tag'].nil? and not track['last_version'].nil?
                      source_version = track['release_tag'].to_s.strip
                      # NOTE: when ruby loads yaml, it turns "foo: :{bar}" into {'foo'=>:"bar"} and "foo: v:{bar}" into {'foo'=>'v:{bar}'}
                      source_version.gsub!(':{version}',track['last_version'].to_s)
                      source_version.gsub!('{version}',track['last_version'].to_s)
                    elsif not track['last_version'].nil?
                      source_version = track['last_version'].to_s
                    end
                    release_version = track['last_version'].to_s.strip
                    unless source_uri.nil? or source_type.nil? or source_version.nil?
                      break
                    end
                  end
                end

                if source_uri.nil? or source_type.nil? or source_version.nil?
                  raise IndexException.new("Could not determine source repo from release repo: " + repo_name + " in rosdistro file: " + rosdistro_filename)
                end
              else
                raise IndexException.new("No source, doc, or release information for repo: " + repo_name+ " in rosdistro file: " + rosdistro_filename)
              end

              status = repo_data.fetch('status', nil)

              # add the release manifest, if found
              unless release_manifest_xml.nil?
                release_manifest_xml.gsub!(':{version}',(release_version or '0.0.0'))
              end
              repos[distro].push({
                  'name' => repo_name,
                  'type' => source_type,
                  'uri' => source_uri,
                  'version' => source_version,
                  'release' => repo_data.key?('release'),
                  'status' => status,
                  'manifest' => release_manifest_xml,
                })
            rescue IndexException => e
              puts "repo_name: #{repo_name} error: #{e}"
              errors[repo_name] << e.to_hash()
            end
          end
        else
          puts"Could not find distribution file for #{distro} at #{rosdistro_filename}"
        end
      end
    end
    File.open(output_path, 'w') { |file| file.write(JSON.pretty_generate(repos)) }
    File.open(errors_path, 'w') { |file| file.write(JSON.pretty_generate(errors)) }
    puts "Completed repo discovery"
    return repos, errors
  end

if __FILE__ == $0
  $fetched_uris = {} # needed by vcs
  params = { path: DISCOVERY_RESULTS, errors: DISCOVERY_ERRORS, config: DEFAULT_CONFIG}
  OptionParser.new do |opts|
    opts.banner = 'Discover ROS repos into discovery.json'
    opts.on('--config first_config.yml,second_config.yml,...', Array)
    opts.on('--path Path to save discovery results')
    opts.on('--errors Path to save discovery errors')
  end.parse!(into: params)
  config = Hash.new
  params[:config].each do |file_name|
    file_obj = YAML.load_file(file_name)
    config.merge!(file_obj)
  end
  config['distros'] = config['ros2_distros'] + config['ros_distros']
  config['old_distros'] = config['old_ros2_distros'] + config['old_ros_distros']
  repos, errors = discover_repos(config, params[:path], params[:errors])
end
