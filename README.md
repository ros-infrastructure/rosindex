ROS Index
=========

A simple static index for known ROS packages hosted at http://index.ros.org/.

It builds in jekyll with a plugin to clone repositories containing ROS packages, scrapes them for information, 
and uses client-side javascript for quick searching and visualization.

[ROS Index](http://index.ros.org/)

* [About](http://index.ros.org/about)
* [Design](http://index.ros.org/about/design)
* [Development](http://index.ros.org/about/development)
* [Contribute](http://index.ros.org/contribute)

## Building the site

### On an Ubuntu 16.04 box

#### Pre-Requisites

##### Dependencies

```bash
sudo sh -c 'echo "deb http://packages.ros.org/ros/ubuntu $(lsb_release -sc) main" > /etc/apt/sources.list.d/ros-latest.list'
apt-key adv --keyserver hkp://ha.pool.sks-keyservers.net:80 --recv-key 421C365BD9FF1F717815A3895523BAEEB01FA116
sudo apt-get update
sudo apt-get install curl git git-svn mercurial nodejs pandoc python3-vcs2l
```

##### Ruby 2.2 via RVM

```bash
curl -L https://get.rvm.io | bash -s stable
# if this fails, add the PGP key and run again
source ~/.rvm/scripts/rvm
rvm requirements
rvm install ruby
rvm rubygems current
```

##### Node.js on Ubuntu 12.04

```bash
sudo apt-get install python-software-properties
sudo apt-add-repository ppa:chris-lea/node.js
sudo apt-get update
sudo apt-get install nodejs
```

##### Ruby Requirements

```bash
gem install bundler
```

#### Clone Source and Install Gems

```bash
git clone git@github.com:ros-infrastructure/rosindex.git --recursive
cd rosindex
bundle install
```

#### Clone repos that are part of rosdistro and build the index

Run:

```bash
make build
```

By default, site will be written to _site. This behavior can be
overriden as follows:

```bash
make build site_path=/path/to/site
```

### On the provided Ubuntu 16.04 container

#### Pre-requisites

##### Docker

See https://docs.docker.com/install/linux/ for details on docker installation.

#### Build docker image

```bash
docker/build.sh
```

#### Build the index inside the container

Run:

```bash
docker/run.sh
make build  # once inside the container
```

Or the following can be used as a shorthand:

```bash
docker/run.sh build_site
```

## Skipping parts of the build

The build process entails four long-running steps:

1. Generating the list of repositories
2. Cloning / Updating the known repositories
3. Scraping the repositories
4. Generating the static pages
5. Generating the lunr search index

Each of the first three steps can be skipped in order to save time when
experimenting with different parts of the pipeline with the following flags in
`_config.yml`:

```yaml
# If true, this skips finding repos based on the repo sources
skip_discover: false
# If true, this skips updating the known repos
skip_update: false
# If true, this skips scraping the cloned repos
skip_scrape: false
# If true, this skips generating the search index
skip_search_index: false
```

Additionally, some make targets are provided for convenience:

- To skip everything but repo discovering:

  ```bash
  make discover
  ```

- To skip everything but repo updates:

  ```bash
  make update
  ```

- To skip everything but repo scraping:

  ```bash
  make scrape
  ```

- To skip everything but a search index build:

  ```bash
  make search-index
  ```

Note that skipping parts of the rosindex build does not interfere with
Jekyll's build process (e.g. generated files are still written to site).


## Serving the site

### Serve the devel (tiny) version locally

Run:

```bash
make serve-devel
```

The following can be used as a shorthand if using
docker containers:

```bash
docker/run.sh test_site
```

### Serve the full version locally

Run:

```bash
make serve
```

**Note:** This requires a minimum of 30GB of free space for the
`checkout` directory.

## Deployment

Deployment is not managed by these tools. It is to be managed
externally e.g. using a local repository as site destination.

## ROS buildfarm integration

ROSIndex qualifies as independent documentation of **'external_site'**
type. Therefore, it can readily be built and deployed as Github Pages by
a *doc_independent* job.
