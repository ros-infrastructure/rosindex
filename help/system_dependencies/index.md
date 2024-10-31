---
layout: page
title: Help for using rosindex system dependencies list and search
permalink: /help/system_dependencies/
breadcrumbs: ['help', 'system_dependencies']
---

# System Dependencies Help

**rosindex** provides a [**System Dependencies**](/search_deps/) page that gives a searchable list of system dependencies within ROS. This help page describes the usage of that page.

ROS dependencies are identifiers that ROS uses to locate additional packages and external libraries that are needed to load a package. See [this tutorial](https://docs.ros.org/en/rolling/Tutorials/Intermediate/Rosdep.html) for a general introduction to dependencies in ROS.

The identifiers of these external libraries come from the [rosdep folder in the rosdistro github site](https://github.com/ros/rosdistro/tree/master/rosdep). These identifiers provide a layer of abstraction between these external libraries and their sources in various library package managers. That way, all ROS packages are using the same names for a particular library, even though it might be called different things in various platforms that are supported by ROS. **rosindex** only shows on this page the external libraries, ROS packages are shown on another page.

## Fields in System Dependencies

- Dependency Name: This is the name that ROS uses to identify the library, for example as used in `<depends>` in `package.xml`. You can click on the name to take you to a detail page for that library.
- Description: This is a description taken from the upstream library package managers for the dependency. Some of these are missing as we do not yet support getting descriptions from all upstream library package managers.
- Dependency used-by count (➡): This is a count of the number of released packages, in all rosdistros, that depend on a particular system dependency. Many of these are zero, as these dependencies may be used by private packages that are not listed in the public rosdistro releases.
- Various platforms (Ubuntu, RHEL, etc.): This shows the availability of the particular library in platforms currently recognized by ROS in a defined tier. Other platforms may also be supported that are not in defined tiers, see the dependency detail page for more info. Windows is not shown as its package management is in flux within ROS. A checkmark means that the dependency is supported in all known versions of a platform, while a dash means that the dependency is supported in a least one version of a platform.

## Searching

**rosindex** uses [lunr search](https://lunrjs.com/) to perform full-text search on information about dependencies. You may get some general help on using lunr search on the [lunr site](https://lunrjs.com/guides/searching.html), but here's a summary:

In the search field, you may enter some search text, and lunr search will search all fields for that value. Items separated by spaces search for either of the values. To specify that a value must occur (logical and), prefix the term with a plus sign "+". Also, both entered searches and their corresponding search index fields treat dashes '-' like spaces, so an item like "libnl-dev" is treated like two search terms, "libnl" and "dev". All seaches are case independent.

**rosindex** searches the following fields within dependencies:
- name: "Dependency Name", the identifier used within ROS to specify a particular dependency.
- description: The description obtained from the upstream package manager.
- dependants: ROS package names that use a particular system dependency.
- platforms: Which platforms (ubuntu, rhel, etc.) support a dependency.
- aliases: These are alternate names that a dependency uses upstream. For example, dependency "cdk" is known as "libcdk5" in debian. You may search for that package either by its ROS name ("cdk") or by its debian alias ("libcdk5").

When a search is performed, the results list is sorted by the quality of the search hit, though this order may be changed by clicking on headers for each column name.

There is additional syntax available on the [lunr search page description](https://lunrjs.com/guides/searching.html) as well, but these details are not usually needed with **rosindex**.

### Example searches

- `boost`: Show the library boost, or other libraries that mention boost
- `name:boost`: Show libraries with 'boost' in the name.
- `rhel`: Show libraries that support rhel (Red Hat Enterprise Linux)
- `network`: Show libraries that mention 'network' in a field (probably in the description)
- `libasio`: Show libraries that use the name 'libasio' in their library package manager (which is used in debian)
- `actionlib`: Show libraries that are used by the 'actionlib' ROS package
