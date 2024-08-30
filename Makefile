site_path ?= _site

devel_config_file=_config_devel.yml

data_dir=_data
cache_dir=_cache
remotes_dir=_remotes
plugins_data_dir=_plugins_data
remotes_file=$(data_dir)/remotes.yml

config_file=_config.yml
index_file=index.yml
discover_config=_config/discover.yml
update_config=_config/update.yml
scrape_config=_config/scrape.yml
search_config=_config/search_index.yml

build: prepare-sources
	bundle exec jekyll build --verbose --trace -d $(site_path) --config=$(config_file),$(index_file)

prepare-sources:
	mkdir -p $(remotes_dir)
	vcs import --input $(remotes_file) --force $(remotes_dir)
	vcs pull $(remotes_dir)

discover: prepare-sources
	bundle exec jekyll build --verbose --trace -d $(site_path) --config=$(config_file),$(index_file),$(discover_config)

update: prepare-sources
	bundle exec jekyll build --verbose --trace -d $(site_path) --config=$(config_file),$(index_file),$(update_config)

scrape: prepare-sources
	bundle exec jekyll build --verbose --trace -d $(site_path) --config=$(config_file),$(index_file),$(scrape_config)

search-index: prepare-sources
	bundle exec jekyll build --verbose --trace -d $(site_path) --config=$(config_file),$(index_file),$(search_config)

serve:
	bundle exec jekyll serve --host 0.0.0.0 --no-watch --trace -d $(site_path) --config=$(config_file),$(index_file) --skip-initial-build

serve-devel:
	bundle exec jekyll serve --host 0.0.0.0 --no-watch --trace -d $(site_path) --config=$(config_file),$(devel_config_file),$(index_file) --skip-initial-build

test-build: prepare-sources
	bundle exec jekyll build --verbose --trace -d $(site_path) --config=$(config_file),$(devel_config_file),$(index_file)

clean-sources:
	rm -rf $(plugins_data_dir)
	rm -rf $(remotes_dir)

clean-cache:
	rm -rf $(cache_dir)

clean: clean-cache clean-sources

