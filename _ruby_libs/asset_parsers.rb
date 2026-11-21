
require 'rexml/document'
require 'rexml/xpath'

def parse_launch_xml(launch_xml, relpath)
  dputs " ---- Parsing launchfile: #{relpath}"

  doc = REXML::Document.new(launch_xml.to_s)

  return {
    'relpath' => relpath,
    'comment' => if doc.comments.length > 0 then doc.comments[0].to_s else '' end,
    'args' => REXML::XPath.each(doc, '//arg').map {|e| e.attributes},
    'includes' => REXML::XPath.each(doc, '//include').map {|e| e.attributes},
    'nodes' => REXML::XPath.each(doc, '//node').map {|e| e.attributes}
  }
end

def extract_launch_data(launch_files, errors_list = nil)
  return [] if launch_files.nil?

  if launch_files.is_a?(Hash)
    return launch_files.map do |relpath, content|
      if content.is_a?(String) && !content.empty?
        begin
          parse_launch_xml(content, relpath.to_s)
        rescue Exception => e
          errors_list << IndexException.new("Failed to parse launchfile #{relpath}: " + e.to_s) if errors_list
          {'relpath' => relpath.to_s, 'comment' => '', 'args' => [], 'includes' => [], 'nodes' => []}
        end
      else
        {'relpath' => relpath.to_s, 'comment' => '', 'args' => [], 'includes' => [], 'nodes' => []}
      end
    end
  end

  return [] unless launch_files.is_a?(Array)

  launch_files.map do |item|
    if item.is_a?(Hash)
      relpath = (item['relpath'] || item['path'] || '').to_s
      content = item['content']
      if content.is_a?(String) && !content.empty?
        begin
          parse_launch_xml(content, relpath)
        rescue Exception => e
          errors_list << IndexException.new("Failed to parse launchfile #{relpath}: " + e.to_s) if errors_list
          {'relpath' => relpath, 'comment' => '', 'args' => [], 'includes' => [], 'nodes' => []}
        end
      else
        {
          'relpath' => relpath,
          'comment' => item['comment'] || '',
          'args' => item['args'] || [],
          'includes' => item['includes'] || [],
          'nodes' => item['nodes'] || []
        }
      end
    else
      {
        'relpath' => item.to_s,
        'comment' => '',
        'args' => [],
        'includes' => [],
        'nodes' => []
      }
    end
  end
end

