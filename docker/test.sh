#!/bin/bash
SCRIPT_DIR=`dirname $( readlink -m $( type -p $0 ))`

# Run the Playwright browser tests (tests/) against the already-built _site.
# Build the site first: docker/run.sh make test-build
# The Playwright image version must match the @playwright/test version in tests/package.json.
#
# Example Usage:
# ./test.sh                          run tests
# ./test.sh --update-snapshots       regenerate visual baselines
# ./test.sh specs/tabs.spec.js       run one spec

PLAYWRIGHT_IMAGE=mcr.microsoft.com/playwright:v1.49.1-noble

docker run --rm --ipc=host \
  --user `id -u`:`id -g` -e HOME=/tmp \
  -v $SCRIPT_DIR/..:/work:rw -w /work/tests \
  $PLAYWRIGHT_IMAGE \
  bash -c 'npm install --no-audit --no-fund && npx playwright test "$@"' -- "$@"
