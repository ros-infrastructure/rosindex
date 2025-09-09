---
layout: page
title: Contribute
permalink: /contribute/
---

# Contribute

There are numerous ways to contribute to ROS Index, either by adding packages,
contributing documentation to existing packages, or adding more analytics to
the website itself.

{% toc 2 %}

## Adding ROS Packages

The majority of repositories listed on ROS Index are discovered via the
<a href="https://github.com/ros/rosdistro" target="_blank">rosdistro</a> system.
As such, the easiest way to add a repository to ROS Index
is to add it to `rosdistro`. While `rosdistro` is used to index distributed
packages, it is also used to automatically create API documentation for source
packages. Note that there is no presumed contract or implied maintainance
responsibility if you add your repository to `rosdistro`.

### Adding a Repository to rosdistro

If you would like you get your code indexed for documentation, click the
button below.

<a type="button" href="{{ "/contribute/add_repo" | prepend: site.baseurl }}" class="btn btn-success">Add a Repository to the Index</a>

### Releasing Binary Packages

Releasing a package for binary distribution is a bit more complicated, and
cannot be done through a web interface. It will, however, make it much
easier for users to run your code. In order to release your repository's
packages, follow the tutorials for the [bloom release automation
tool](https://docs.ros.org/en/rolling/How-To-Guides/Releasing/Releasing-a-Package.html) on the ROS.org.


## Opting out of Indexing

If you do not want a branch of your repository to be shown on ROS Index, simply
create a file called `.rosindex_ignore` at the root of the repository in that
branch:

```bash
touch .rosindex_ignore
```

If you do not want a single package in a repository indexed, you can create
a `.rosindex_ignore` file at the root of that package. If this does not work or
you want some other information removed from ROS Index, please [create an issue
on GitHub](https://github.com/ros-infrastructure/rosindex/issues/new?title=%5BREMOVAL%20REQUEST%5D%20)
describing what you would like removed.

## Contribute to the ROS Index Website

ROS Index is a statically-generated website which is stored and hosted
entirely on GitHub. The website uses the [Jekyll](http://jekyllrb.com) framework with some custom plugins
for cloning and scraping known ROS repositories. Since it uses custom
plugins, and generation is space- and computationally-expensive, it needs
to be generated offline, and then uploaded to GitHub's severs.

Since the ROS Index website is completely open-source, issues, feature
requests, and especially pull requests are welcome.

<a href="https://github.com/ros-infrastructure/rosindex/issues/new" target="_blank" class="btn btn-success">Post an Issue</a>

For more details on developing ROS Index, see [development]({{ "/about/development" | prepend: site.baseurl }}).

