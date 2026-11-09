#!/bin/bash

REPO_PATH=${1:-`pwd`}
SITE_PATH=${2:-${REPO_PATH}/_site}
make -C $REPO_PATH test-serve site_path=$SITE_PATH
