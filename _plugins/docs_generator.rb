require 'addressable'
require 'fileutils'
require 'nokogiri'
require 'uri'

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

      global_content = {}

      css_files = repo_build["context"]["css_files"]
      global_content["css_uris"] = css_files.map do |css_file|
        css_uri = URI(css_file)
        if not css_uri.absolute?
          css_uri = File.join(
            site.baseurl,
            "doc/#{repo_name}",
            css_uri.path
          )
        end
        css_uri.to_s
      end

      script_files = repo_build["context"]["script_files"]
      global_content["script_uris"] = script_files.map do |script_file|
        script_uri = URI(script_file)
        if not script_uri.absolute?
          script_uri = File.join(
            site.baseurl,
            "doc/#{repo_name}",
            script_uri.path
          )
        end
        script_uri.to_s
      end

      documents = {}
      repo_build['documents'].each do |permalink, local_content|
        # A document will be processed _before_ any of its child documents
        # as DocPageGenerator::build_with_sphinx enforces this ordering.
        parent_path = permalink.rpartition('/').first
        while not parent_path.empty? and not documents.key? parent_path
          parent_path = parent_path.rpartition('/').first
        end
        parent_page = documents.fetch(parent_path, nil)

        content = global_content.clone
        content.update(local_content)

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

      repo_build['static_files'].each do |permalink, path|
        site.static_files << RelocatableStaticFile.new(
          site, site.source,
          File.dirname(path), File.basename(path),
          "doc/#{repo_name}/#{permalink}"
        )
      end
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
    command = "LC_ALL=C.UTF-8 python3 -m sphinx -vvv -b json -c #{repo_path} #{input_path} #{output_path}"
    pid = Kernel.spawn(command)
    Process.wait pid

    repo_build = Hash.recursive

    global_context_path = File.join(output_path, "globalcontext.json")
    repo_build["context"] = JSON.parse(File.read(global_context_path))

    repo_build["context"]["css_files"].each do |css_file|
      css_uri = URI(css_file)
      if not css_uri.absolute?
        css_file_permalink = css_uri.path
        css_file_path = File.join(output_path, css_file_permalink)
        repo_build['static_files'][css_file_permalink] = css_file_path
      end
    end

    repo_build["context"]["script_files"].each do |script_file|
      script_uri = URI(script_file)
      if not script_uri.absolute?
        script_file_permalink = script_uri.path
        script_file_path = File.join(output_path, script_file_permalink)
        repo_build['static_files'][script_file_permalink] = script_file_path
      end
    end

    Dir.glob(File.join(output_path, "{_images/*.*,_downloads/**/*.*}"),
             File::FNM_PATHNAME).each do |static_file_path|
      static_file_path = Pathname.new(static_file_path)
      static_file_permalink = static_file_path.relative_path_from(output_path)
      repo_build["static_files"][static_file_permalink] = static_file_path
    end

    repo_index_pattern = repo_data.fetch("index_pattern", ["*.rst", "**/*.rst"])
    repo_ignore_pattern = ["**/search.fjson", "**/searchindex.fjson", "**/genindex.fjson"]
    repo_ignore_pattern.push(*repo_data.fetch("ignore_pattern", []))
    Dir.glob(File.join(output_path, '**/*.fjson'),
             File::FNM_PATHNAME).each do |json_filepath|
      json_filepath = Pathname.new(json_filepath)
      next if repo_ignore_pattern.any? do |pattern|
        File.fnmatch?(pattern, json_filepath, File::FNM_PATHNAME)
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
          File.fnmatch?(pattern, src_path.relative_path_from(input_path),
                        File::FNM_PATHNAME)
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
          File.fnmatch?(pattern, first_sourcename, File::FNM_PATHNAME)
        end || -1
        second_sourcename = b[1]['sourcename'] || ''
        second_order = repo_index_pattern.index do |pattern|
          File.fnmatch?(pattern, second_sourcename, File::FNM_PATHNAME)
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
    return repo_build
  end
end
