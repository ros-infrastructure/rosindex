site_path ?= _site

devel_config_file=_config_devel.yml

data_dir=_data
cache_dir=_cache
remotes_dir=_remotes
plugins_data_dir=_plugins_data
remotes_file=$(data_dir)/remotes.yml

config_file=_config.yml
index_file=index.yml
update_config=_config/update.yml
scrape_config=_config/scrape.yml
search_config=_config/search_index.yml

.DEFAULT_GOAL := build
.PHONY: build rebuild-dep-descriptions prepare-sources discover test-discover \
        update scrape serve test-serve test-build clean-sources clean-cache clean \
				rosdistro-cache rosdistro-cache-devel update-rosdistro

CONFIG_FILES ?= $(config_file),$(index_file)
DEVEL_CONFIG_FILES = $(config_file),$(index_file),$(devel_config_file)

ROSDISTRO_CACHE_CONFIG := _artifacts/rosdistro_cache_config.yaml
ROSDISTRO_CACHE_SCRIPT := _scripts/rosdistro_cache.py
PIP_FILE := _artifacts/pip_packages.json
PIP_SCRIPT := _scripts/pip_packages.py
PIP_MAX_AGE_HOURS ?= 20
DEBIAN_FILE := _artifacts/debian_packages.json
DEBIAN_SCRIPT := _scripts/debian_descriptions.rb
DISCOVERY_SCRIPT = _scripts/discovery.py
DISCOVERY_RESULTS = _artifacts/discovery.json
DISCOVERY_ERRORS = _artifacts/discovery_errors.json

ROSDISTRO_ENV = _artifacts/rosdistro_env

$(ROSDISTRO_ENV):
	python3 -m venv $(ROSDISTRO_ENV)
	$(ROSDISTRO_ENV)/bin/python -m pip install git+https://github.com/ros-infrastructure/rosdistro.git@extended_cache_refactor

update-rosdistro: $(ROSDISTRO_ENV)
	$(ROSDISTRO_ENV)/bin/python -m pip install --upgrade --force-reinstall --no-deps git+https://github.com/ros-infrastructure/rosdistro.git@extended_cache_refactor

rosdistro-cache: $(ROSDISTRO_ENV)
	@echo "Get rosdistro cache files"
	$(ROSDISTRO_ENV)/bin/python $(ROSDISTRO_CACHE_SCRIPT) --config=$(CONFIG_FILES) --cache-dir=$(cache_dir) --cache-config-out=$(ROSDISTRO_CACHE_CONFIG)

rosdistro-cache-devel: $(ROSDISTRO_ENV)
	@echo "Get rosdistro cache files (devel config)"
	$(ROSDISTRO_ENV)/bin/python $(ROSDISTRO_CACHE_SCRIPT) --config=$(DEVEL_CONFIG_FILES) --cache-dir=$(cache_dir) --cache-config-out=$(ROSDISTRO_CACHE_CONFIG)

$(PIP_FILE):
	@echo "Get pip descriptions file"
	python3 $(PIP_SCRIPT) --output=$(PIP_FILE) --max-age-hours=$(PIP_MAX_AGE_HOURS)

$(DISCOVERY_RESULTS): $(ROSDISTRO_ENV)
	@echo "Ensure rosdistro cache files exist"
	$(ROSDISTRO_ENV)/bin/python $(ROSDISTRO_CACHE_SCRIPT) --config=$(CONFIG_FILES) --cache-dir=$(cache_dir) --cache-config-out=$(ROSDISTRO_CACHE_CONFIG) --skip-if-present
	@echo "Rebuild discovery file that contains discovered repos"
	$(ROSDISTRO_ENV)/bin/python $(DISCOVERY_SCRIPT) --config=$(CONFIG_FILES) --path=$(DISCOVERY_RESULTS) --errors=$(DISCOVERY_ERRORS) --cache-dir=$(cache_dir)
  
rebuild-dep-descriptions: prepare-sources
	@echo "Update pip descriptions file"
	python3 $(PIP_SCRIPT) --output=$(PIP_FILE) --max-age-hours=$(PIP_MAX_AGE_HOURS)
	@echo "rebuild debian descriptions file"
	ruby $(DEBIAN_SCRIPT)

$(DEBIAN_FILE):
	@echo "Get debian descriptions file"
	ruby $(DEBIAN_SCRIPT)

discover: $(ROSDISTRO_ENV)
	@echo "Ensure rosdistro cache files exist"
	$(ROSDISTRO_ENV)/bin/python $(ROSDISTRO_CACHE_SCRIPT) --config=$(CONFIG_FILES) --cache-dir=$(cache_dir) --cache-config-out=$(ROSDISTRO_CACHE_CONFIG) --skip-if-present
	@echo "Rebuild discovery file that contains discovered repos"
	$(ROSDISTRO_ENV)/bin/python $(DISCOVERY_SCRIPT) --config=$(CONFIG_FILES) --path=$(DISCOVERY_RESULTS) --errors=$(DISCOVERY_ERRORS) --cache-dir=$(cache_dir)

test-discover: $(ROSDISTRO_ENV)
	@echo "Ensure rosdistro cache files exist (devel config)"
	$(ROSDISTRO_ENV)/bin/python $(ROSDISTRO_CACHE_SCRIPT) --config=$(DEVEL_CONFIG_FILES) --cache-dir=$(cache_dir) --cache-config-out=$(ROSDISTRO_CACHE_CONFIG) --skip-if-present
	@echo "Rebuild discovery file that contains discovered repos (devel config)"
	$(ROSDISTRO_ENV)/bin/python $(DISCOVERY_SCRIPT) --config=$(DEVEL_CONFIG_FILES) --path=$(DISCOVERY_RESULTS) --errors=$(DISCOVERY_ERRORS) --cache-dir=$(cache_dir)

build: rebuild-dep-descriptions discover prepare-sources
	bundle exec jekyll build --verbose --trace -d $(site_path) --config=$(config_file),$(index_file)

prepare-sources:
	mkdir -p $(remotes_dir)
	vcs import --input $(remotes_file) --force $(remotes_dir)
	vcs pull $(remotes_dir)

update: prepare-sources
	bundle exec jekyll build --verbose --trace -d $(site_path) --config=$(config_file),$(index_file),$(update_config)

scrape: prepare-sources
	bundle exec jekyll build --verbose --trace -d $(site_path) --config=$(config_file),$(index_file),$(scrape_config)

search-index: prepare-sources
	bundle exec jekyll build --verbose --trace -d $(site_path) --config=$(config_file),$(index_file),$(search_config)

serve:
	bundle exec jekyll serve --host 0.0.0.0 --no-watch --trace -d $(site_path) --config=$(config_file),$(index_file) --skip-initial-build

test-serve:
	bundle exec jekyll serve --host 0.0.0.0 --no-watch --trace -d $(site_path) --config=$(DEVEL_CONFIG_FILES) --skip-initial-build

test-build: $(PIP_FILE) $(DEBIAN_FILE) test-discover prepare-sources
	bundle exec jekyll build --verbose --trace -d $(site_path) --config=$(DEVEL_CONFIG_FILES)

clean-sources:
	rm -rf $(plugins_data_dir)
	rm -rf $(remotes_dir)

clean-cache:
	rm -rf $(cache_dir)

clean: clean-cache clean-sources

