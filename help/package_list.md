---
layout: page
title: Help for using rosindex package list and search
permalink: /help/package_list/
breadcrumbs: ['help']
---

# Package List and Search Help

**rosindex** provides a [**Package List**](/?search_packages=true) page that gives a searchable list of packages within ROS. This help page describes the usage of that page.

## Fields in Package List

- Package: Package name.
- Description: Package description.
- Release status (★): Release status of the package. A checkmark signifies the package is released.
- Last commit date (📅): The last date a commit was made to the package's repository.
- Package dependency count (⬅): How many packages this package depends on.
- Package used by count(➡): How many packages use this package as a dependency.
- Authors: Names listed in package.xml as authors.
- Maintainers: Names listed in package.xml as maintainers.
- Repo: Repository containing this package.
- Org: Organization that is the parent of the package's repository.

## Searching

**rosindex** uses [lunr search](https://lunrjs.com/) to perform full-text search on information about packages. You may get some general help on using lunr search on the [lunr site](https://lunrjs.com/guides/searching.html), but here's a summary:

In the search field, you may enter some search text, and lunr search will search all fields for that value. Items separated by spaces search for either of the values. To specify that a value must occur (logical and), prefix the term with a plus sign "+". Also, both entered searches and their corresponding search index fields treat dashes '-' like spaces, so an item like "ros-industrial" is treated like two search terms, "ros" and "industrial". All searches are case independent.

The package name is split by underscore (_), and those individual terms are added as "tags" that are included in the search. So searching for "msgs" will find packages whose name includes "_msgs", such as "control_msgs".

**rosindex** searches the following fields within packages. These fields are also displayed, see above for their description:
- package
- description
- maintainers
- authors
- repo
- org

These fields are additionally searched:
- readme: The 'readme' file included in the package repository.
- tags: These mostly contains the page name split by '_', so that for example the package with name "avt_vimbra_camera" would have tags 'avt', 'vimbra', and 'camera'. (A few packages have explicit tags defined, but most do not.)
- released: Is the package released? Has a value 'released' if released, otherwise empty.

### Example searches

- `ament_package`: packages containing 'ament_package' in any field (shows package ament_package and one other)
- `package:ament_package` packages with the name 'ament_package' (shows only the package ament_package)
- `authors:josh maintainers:josh` packages with 'Josh' as either an author, or a maintainer.
- `org:ros2`: packages in the organization ros2
- `msgs`: packages containing 'msgs' in any field. Since packages names are split by '_' into tags, any package with a name like *_msgs will have 'msgs' as a tag, and thus show in this search result.

