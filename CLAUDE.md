# CLAUDE.md

## Overview

This repository contains a Jekyll documentation generator for packages in the ROS 2 ecosystem (ROS Index). It discovers repositories, scrapes package metadata and docs, and generates a static website.

Key locations:
- `_plugins/` – Jekyll plugins (main logic in `rosindex_generator.rb`)
- `_ruby_libs/` – Ruby helpers, including `discovery.rb`
- `_scripts/` – helper scripts (pip/debian package descriptions)
- `_config.yml`, `_config_devel.yml`, `index.yml`, `_config/` – Jekyll/site configuration
- `_data/remotes.yml` – repositories imported into `_remotes/` via `vcs`
- `_layouts/`, `_includes/`, `_sass/` – site templates and styles

## Building

- **Always build under Docker** using `docker/build.sh` (builds the `rosindex/rosindex` image). Use `docker/run.sh <command>` to run commands inside the container, e.g. `docker/run.sh make test-build`.
- **A full build (`make build`) is impractical during development.** Use the Makefile target `test-build` instead; it uses `_config_devel.yml` to limit the scope.
- After a build, the output is a static website in `_site/`. That folder is sufficient to host or inspect the result; no further server is required.

## Bootstrap

The site uses Bootstrap 5.3 with the Bootswatch Lumen theme, loaded from cdn.jsdelivr.net in `_layouts/default.html` (`bootswatch@<ver>/dist/lumen/bootstrap.min.css`, `bootstrap@<ver>/dist/js/bootstrap.bundle.min.js` which includes Popper, and `bootstrap-icons@<ver>/font/bootstrap-icons.min.css`). There is no npm/SCSS build for Bootstrap; to upgrade, bump the pinned versions in those URLs. Builds and UI tests therefore need network access.

- The site was migrated from Bootstrap 3 (Lumen 3.3.2). The top of `_sass/_base.scss` holds overrides that keep the Lumen 3 look (14px root font, link underline on hover, table and card spacing, row gutters); check them when upgrading.
- jQuery is still used by the site's own JS, but Bootstrap components are driven through `data-bs-*` attributes or the native API (`bootstrap.Tab.getOrCreateInstance(el).show()`), not jQuery plugins.

## UI tests

`tests/` holds Playwright browser tests that pin down behavior (tabs, dropdowns, distro switch, responsive layout, visual snapshots).

- Build first (`docker/run.sh make test-build`), then run `docker/test.sh`. It runs the tests in the official Playwright Docker image (the Jekyll image has no npm or browsers) against `_site/`, served with `python3 -m http.server`. Extra arguments pass through, e.g. `docker/test.sh specs/tabs.spec.js`.
- `docker/test.sh --update-snapshots` regenerates the visual baselines in `tests/specs/__screenshots__/`; only do this deliberately (baselines should be recorded on the current Bootstrap version). Baselines are rendered in the container, so don't generate them on the host.
- Tests run in Chromium, Firefox and WebKit (`--project=firefox` runs one). Visual baselines are Chromium only: tests tagged `@visual` are skipped in the other engines.
- Tests assert on behavior, not Bootstrap class names. `@playwright/test` in `tests/package.json` must match the image tag in `docker/test.sh`.
