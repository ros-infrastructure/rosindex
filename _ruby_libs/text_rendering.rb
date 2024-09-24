# Tools for rendering of markdown and rst documents

require 'addressable'
require 'nokogiri'
require 'pandoc-ruby'

# Converts RST to Markdown
def rst_to_md(rst)
  begin
    # For some reason, Pandoc is converting UTF-8 into ASCII which then kills kramdown
    return PandocRuby.convert(rst, :from => :rst, :to => :markdown).force_encoding(Encoding::UTF_8)
  rescue Exception => e
    return "Could not convert RST to MD: "+e.to_s
  end
end

# Modifies markdown local links so that they link to github user content
def fix_local_links(text, raw_uri, browse_uri)
  readme_doc = Nokogiri::HTML(text)
  readme_doc.css("img[src]").each do |img|
    begin
      unless Addressable::URI.parse(img['src']).absolute?
        img['src'] = raw_uri + "/" + img['src']
      end
    rescue Addressable::URI::InvalidURIError
      puts " --- WARNING: Markdown image link is ill-formed and had to be disabled: #{img['src'].to_s}".yellow
      # If alt is defined displays it, removing the img otherwise
      unless img['alt'].nil? || img['alt'].empty?
        img.replace(img['alt'])
      else
        img.remove
      end
    end
  end
  readme_doc.css("a[href]").each do |a|
    begin
      unless Addressable::URI.parse(a['href']).absolute?
        a['href'] = browse_uri + "/" + a['href']
      end
    rescue Addressable::URI::InvalidURIError
      puts " --- WARNING: Markdown link is ill-formed and had to be disabled: #{a['href'].to_s}".yellow
      # Removes the ill-formed href leaving the only base word
      a.replace(a.content)
    end
  end
  readme_doc.at('body').inner_html
end

# Renders markdown to html (and apply some required tweaks)
def render_md(site, readme)
  begin
    # Get the markdown converter
    mdconverter = if site.respond_to?(:find_converter_instance)
                    site.find_converter_instance(Jekyll::Converters::Markdown)
                  else
                    site.getConverterImpl(Jekyll::Converters::Markdown)
                  end
    readme.gsub! "```","\n```"
    readme.gsub! '```shell','```bash'
    return mdconverter.convert(readme)
  rescue Exception =>e
    return 'Could not convert readme: <pre>'+e.to_s+'</pre>'
  end
end


def get_md_rst_txt(site, path, glob, raw_uri, browse_uri)

  file_md = nil

  file_files = Dir.glob(File.join(path,glob), File::FNM_CASEFOLD)
  file_files.each do |file_path|
    case File.extname(file_path)
    when '.md'
      file_md = IO.read(file_path, :encoding=>'utf-8')
    when '.rst'
      file_rst = IO.read(file_path, :encoding=>'utf-8')
      file_md = rst_to_md(file_rst)
    when ''
      if not File.directory?(file_path)
        file_txt = IO.read(file_path, :encoding=>'utf-8')
        file_md = "```\n" + file_txt + "\n```"
      else
        next
      end
    else
      file_txt = IO.read(file_path, :encoding=>'utf-8')
      file_md = "```\n" + file_txt + "\n```"
    end
    break
  end

  if file_md
    # read in the file and fix links
    file_html = render_md(site, file_md)
    file_html = '<div class="rendered-markdown">'+file_html+"</div>"
    file_rendered = fix_local_links(file_html, raw_uri, browse_uri)
  else
    file_rendered = nil
  end

  return file_rendered, file_md
end
