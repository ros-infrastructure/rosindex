
require 'fileutils'
require 'json'
require_relative './common'

def precompile_lunr_index(site, index, ref, fields, output_dir, shard_count = 1)
  build_index_cmd = File.join(
    site.source, 'node_modules',
    'lunr-index-build', 'bin',
    'lunr-index-build'
  )
  build_index_args = ['-r', ref] + fields.map { |f| ['-f', f] }.flatten
  build_cmd_line = "#{build_index_cmd} #{build_index_args.join(' ')}"

  output_dirpath = File.join(site.dest, output_dir)
  FileUtils.mkdir_p(site.dest) unless File.directory?(site.dest)
  FileUtils.mkdir_p(output_dirpath) unless File.directory?(output_dirpath)
  shard_size = index.length / shard_count
  if shard_size == 0 then shard_size = 1 end

  Enumerator.new do |enum| 
    shards = index.each_slice(shard_size).with_index.collect do |index_slice, i|
      dputs("Building lunr index shard #{i}...")
      index_filename = "index.#{i}.json"
      data_filename = "data.#{i}.json"
      data_filepath = File.join(output_dirpath, data_filename)
      File.open(data_filepath, 'w') do |data_file|
        data_file.write(JSON.generate(index_slice))
      end
      enum.yield SearchIndexFile.new(site, site.dest, output_dir, data_filename)
      dputs("Index data written to #{data_filename}.")
      index_filepath = File.join(output_dirpath, index_filename)
      dputs("#{build_cmd_line} < #{data_filepath} > #{index_filepath}")
      pid = spawn(build_cmd_line, :in=>data_filepath, :out=>[index_filepath, 'w'])
      Process.waitpid(pid)
      enum.yield SearchIndexFile.new(site, site.dest, output_dir, index_filename)
      dputs("Index written to #{output_dir}/#{index_filename}.")
      {:index => index_filename, :data => data_filename}
    end
    shards_filename = "shards.json"
    shards_filepath = File.join(output_dirpath, shards_filename)
    File.open(shards_filepath, 'w') do |shards_file|
      shards_file.write(JSON.generate(shards))
    end
    enum.yield SearchIndexFile.new(site, site.dest, output_dir, shards_filename)
    dputs("Shards list written to #{output_dir}/#{shards_filename}.")
  end
end
