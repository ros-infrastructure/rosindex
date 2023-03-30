FROM ubuntu:focal

ARG user=rosindex
ARG uid=1000

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update && \
    apt-get install --no-install-recommends -y \
        gnupg && \
    rm -rf /var/lib/apt/lists/*

COPY docker/image/ros.asc /tmp/ros.asc
RUN echo "deb http://packages.ros.org/ros/ubuntu focal main" > \
         /etc/apt/sources.list.d/ros-latest.list
RUN apt-key add /tmp/ros.asc

RUN apt-get update && \
    apt-get install --no-install-recommends -y \
        apt-utils \
        build-essential \
        cmake \
        curl \
        git-all \
        git-svn \
        libgit2-dev \
        libpthread-stubs0-dev \
        libssl-dev \
        libz-dev \
        mercurial \
        nodejs \
        openssl \
        pandoc \
        pkg-config \
        python3-pip \
        python3-vcstool \
        ruby \
        ruby-dev \
        rubygems-integration && \
    rm -rf /var/lib/apt/lists/*

RUN gem install bundle
RUN pip3 install --upgrade setuptools pip
RUN pip3 install sphinx sphinx-reredirects gitpython

RUN ln -s `which nodejs` /usr/local/bin/node

COPY docker/image/build_site.sh /usr/local/bin/build_site
COPY docker/image/test_site.sh /usr/local/bin/test_site
COPY docker/image/update_site.sh /usr/local/bin/update_site
COPY docker/image/git_add_files.py /usr/local/bin/git_add_files

RUN useradd -u $uid -m $user
ENV HOME=/home/$user
WORKDIR $HOME
COPY Gemfile* .bundle/
RUN chown -R $user:$user .

RUN gem install bundler
USER $user
ENV BUNDLE_PATH=$HOME/.bundle
ENV BUNDLE_GEMFILE=$HOME/.bundle/Gemfile
RUN bundle install

RUN git config --global user.name "rosindex"
RUN git config --global user.email "rosindex@build.ros.org"

# The environment variables REPO and SITE should be set when running this container.
# REPO: The path to this source repository in the container
# SITE: The path to the destination repository in the container
ENV REPO ""
ENV SITE ""
CMD update_site ${REPO} ${SITE}
