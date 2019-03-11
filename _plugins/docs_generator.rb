require 'addressable'
require 'fileutils'
require 'nokogiri'

require_relative '../_ruby_libs/pages'
require_relative '../_ruby_libs/lunr'

class Hash
  def self.recursive
    new { |hash, key| hash[key] = recursive }
  end
end

class DocPageGenerator < Jekyll::Generator
  safe true

  def initialize(config = {})
    super(config)
  end

  def generate(site)
    all_repos = site.data['remotes']['repositories']
    puts ("Scraping documentation pages from repositories...").blue
    documents_index = []
    site.config['docs_repos'].each do |repo_name, repo_options|
      next unless all_repos.key? repo_name

      repo_path = Pathname.new(File.join('_remotes', repo_name))
      repo_data_path = File.join(repo_path, 'rosindex.yml')
      repo_data = File.file?(repo_data_path) ? YAML.load_file(repo_data_path) : {}
      repo_data.update(all_repos[repo_name])

      repo_build = build_with_sphinx(repo_name, repo_path, repo_data)

      documents = {}
      repo_build['documents'].each do |permalink, content|
        parent_path, * = permalink.rpartition('/')
        parent_page = documents.fetch(parent_path, nil)
        if parent_page.nil? and repo_options.key? 'description'
          content['title'] = repo_options['description']
        end
        documents[permalink] = document = DocPage.new(
          site, parent_page, "doc/#{repo_name}/#{permalink}", content
        )
        documents_index << {
          'id' => documents_index.length,
          'url' => document.url,
          'title' => Nokogiri::HTML(document.data['title']).text,
          'content' => Nokogiri::HTML(content['body'], &:noent).text
        } unless site.config['skip_search_index'] if document.data['indexed']

        site.pages << document
      end
      repo_build['images'].each do |permalink, path|
        site.static_files << RelocatableStaticFile.new(
          site, site.source,
          File.dirname(path), File.basename(path),
          "doc/#{repo_name}/#{permalink}"
        )
      end
    end
    unless site.config['skip_search_index']
      puts ("Generating lunr index for documentation pages...").blue
      reference_field = 'id'
      indexed_fields = ['title', 'content']
      site.static_files.push(*precompile_lunr_index(
        site, documents_index, reference_field, indexed_fields,
        "search/docs/", site.config['search_index_shards'] || 1
      ).to_a)
    end
  end

  def generate_edit_url(repo_data, original_filepath)
    is_https = repo_data['url'].include? "https"
    is_github = repo_data['url'].include? "github.com"
    is_bitbucket = repo_data['url'].include? "bitbucket.org"
    unless is_github or is_bitbucket
      raise ValueError("Cannot generate edition URL. Unknown organization for repository: #{repo_data['url']}")
    end
    if is_https
      uri = URI(repo_data['url'])
      host = uri.host
      organization, repo = uri.path.split("/").reject { |c| c.empty? }
    else # ssh
      host, path = repo_data['url'].split("@")[1].split(":")
      organization, repo = path.split("/")
    end
    repo.chomp!(".git") if repo.end_with? ".git"
    if is_github
      edit_url = "https://#{host}/#{organization}/#{repo}/edit/#{repo_data['version']}"
      return File.join(edit_url, original_filepath)
    elsif is_bitbucket
      edit_url = "https://#{host}/#{organization}/#{repo}/src/#{repo_data['version']}"
      return File.join(edit_url, original_filepath) +
             "?mode=edit&spa=0&at=#{repo_data['version']}&fileviewer=file-view-default"
    end
  end

  def build_with_sphinx(repo_name, repo_path, repo_data)
    input_path = Pathname.new(File.join(
      repo_path, repo_data.fetch('sources_dir', '.')
    ))
    output_path = Pathname.new(File.join(repo_path, '_build'))
    FileUtils.rm_r(output_path) if File.directory? output_path
    FileUtils.makedirs(output_path)
    command = "python3 -m sphinx -b json -c #{repo_path} #{input_path} #{output_path}"
    pid = Kernel.spawn(command)
    Process.wait pid

    repo_build = Hash.recursive
    repo_index_pattern = repo_data.fetch("index_pattern", ["*.rst", "**/*.rst"])
    repo_ignore_pattern = ["**/search.fjson", "**/searchindex.fjson", "**/genindex.fjson"]
    repo_ignore_pattern.push(*repo_data.fetch("ignore_pattern", []))
    Dir.glob(File.join(output_path, '**/*.fjson'),
             File::FNM_CASEFOLD).each do |json_filepath|
      json_filepath = Pathname.new(json_filepath)
      next if repo_ignore_pattern.any? do |pattern|
        File.fnmatch?(pattern, json_filepath)
      end
      content = JSON.parse(File.read(json_filepath))
      rel_path = json_filepath.relative_path_from(output_path).sub_ext(".rst")
      src_path = Pathname.new(File.join(input_path, rel_path))
      # Check if the fjson has a rst counterpart
      if File.exists? src_path then
        content["edit_url"] = generate_edit_url(
          repo_data, src_path.relative_path_from(repo_path)
        )
        content["indexed_page"] = repo_index_pattern.any? do |pattern|
            File.fnmatch?(pattern, src_path.relative_path_from(input_path))
        end
        content["sourcename"] = src_path.relative_path_from(input_path)
      end
      permalink = content["current_page_name"]
      if File.basename(permalink) == "index"
        permalink = File.dirname(permalink)
        permalink = '' if permalink == '.'
      end
      repo_build['documents'][permalink] = content
    end
    repo_build['documents'] = repo_build['documents'].sort do |a, b|
      first_depth = a[0].count('/')
      second_depth = b[0].count('/')
      if first_depth == second_depth
        first_sourcename = a[1]['sourcename'] || ''
        first_order = repo_index_pattern.index do |pattern|
          File.fnmatch?(pattern, first_sourcename)
        end || -1
        second_sourcename = b[1]['sourcename'] || ''
        second_order = repo_index_pattern.index do |pattern|
          File.fnmatch?(pattern, second_sourcename)
        end || -1
        if first_order == second_order
          first_title = a[1]['title'] || ''
          second_title = b[1]['title'] || ''
          first_title <=> second_title
        else
          first_order <=> second_order
        end
      else
        first_depth <=> second_depth
      end
    end
    Dir.glob(File.join(output_path, '_images/*.*'),
             File::FNM_CASEFOLD).each do |image_path|
      image_path = Pathname.new(image_path)
      image_permalink = image_path.relative_path_from(output_path)
      repo_build['images'][image_permalink] = image_path
    end
    return repo_build
  end
end
