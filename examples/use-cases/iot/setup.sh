#!/bin/bash

# Apache v2 license
# Copyright (C) <2019> Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -euo pipefail

GSG_DIR="$(dirname "$(readlink -f "$0")")"
if [ -f "$GSG_DIR/helpers.sh" ]; then
  . "$GSG_DIR/helpers.sh"
else
  echo "Error: Unable to find $GSG_DIR/helpers.sh script!"
  exit 1
fi
cd $GSG_DIR

# Customizable options
PARALLEL_BUILD=${PARALLEL_BUILD:-0}
SKIP_GIT_UPDATES=${SKIP_GIT_UPDATES:-0}
GITHUB_URL=${GITHUB_URL:-https://github.com}
GITHUB_ORG=${GITHUB_ORG:-intel}
REPO_PREFIX=${REPO_PREFIX:-rsp-sw-toolkit-im-suite-}
POE_CAMERA=${POE_CAMERA:-true}
QUIET=${QUIET:-0}
DEBUG=${DEBUG:-0}
COLOR=${COLOR:-1}
STYLE=${STYLE:-1}
MAX_LOG_FOLDERS=${MAX_LOG_FOLDERS:-5}
DATE_FORMAT=${DATE_FORMAT:-}
IS_RUNNING_UPDATE=${IS_RUNNING_UPDATE:-0}
SKIP_UPDATE=${SKIP_UPDATE:-0}
HELP=${HELP:-0}
PARAMS=()

printHelp() {
  printf "\
Usage: %s [options...]

  --usb   --usb-camera    run loss-prevention service using usb camera instead of IP Camera
  -p      --parallel      run build and deploy in parallel
  -su     --skip-update   skip checking updates for this script

  --url     --github-url  <url>     set the base url to clone from github, including git:// or https://
  --org     --github-org  <org>     set the github organization name (first path after base-url)
  --prefix  --repo-prefix <prefix>  set the prefix to append to each repo-name (default is no prefix)

" "$0"
}

printAdditionalHelp() {
  printf "\
Additional Options:
  -sx   --set-x          run with 'set -x' enabled for debugging
  -d    --debug          run with debug logging enabled
  -nc   --no-color       do not print output using ANSI color
  -ns   --no-style       do not print output using ANSI styling
  -na   --no-ansi        do not print output using ANSI color or styling
  -h    --help           print help message

"
}

parseArguments() {
  while (( "$#" )); do
    case "$1" in
      -nc|--no-color) COLOR=0; shift ;;
      -ns|--no-stlye) STYLE=0; shift ;;
      -na|--no-ansi) STYLE=0; COLOR=0; shift ;;
      -p|--parallel) PARALLEL_BUILD=1; shift ;;
      -su|--skip-update) SKIP_UPDATE=1; shift ;;
      -sx|--set-x) SET_X=1; shift ;;
      -d|--debug) DEBUG=1; shift ;;
      --url|--github-url) GITHUB_URL="$2"; shift 2 ;;
      --org|--github-org) GITHUB_ORG="$2"; shift 2 ;;
      --prefix|--repo-prefix) REPO_PREFIX="$2"; shift 2 ;;
      --usb|--usb-camera) POE_CAMERA="false"; shift ;;

      -h|--help) HELP=1; shift ;;

      --) shift; break ;; # end argument parsing
      -*|--*=) unsupportedFlag $1 ;;
      *) PARAMS=("${PARAMS[@]}" "$1"); shift ;;
    esac
  done
}

BEGIN_SECONDS=$(( $(date +%s) ))

parseArguments "$@"
setupColorsAndStyle
checkAndPrintHelp

SET_X=${SET_X:-0}
if [ $SET_X -eq 1 ]; then
  set -x
fi

printRSPBanner
warnIfRootUser
checkForScriptUpdates "$@"
rotateLogFolders
# check this early to avoid prompts later
sudoPrompt

PROJECTS_DIR=$HOME/projects
mkdir -p $PROJECTS_DIR

# Clone
# NOTE: Do NOT run the clones in parallel, due to an issue with the git credential helper locking mechanism
#       If done in parallel you will see 'unable to get credential storage lock: File exists', and some of
#       the repos and/or submodules will fail to clone correctly
(cloneAndUpdateRepo inventory-suite -b master --recurse-submodules; updateRepoSubmodules inventory-suite)
(cloneAndUpdateRepo tempo-device-service)
(cloneAndUpdateRepo food-safety-service)
(cloneAndUpdateRepo loss-prevention-service)
wait

# Dependencies
installDependencies |& prefixOutput "setup" "| deps"
checkDependencies |& prefixOutput "setup" "| deps"

# export this now, used by loss-prevention to know how to deploy the services
export POE_CAMERA=$POE_CAMERA

# Build
installSecrets |& prefixOutput "setup" "| secrets"
if [ $PARALLEL_BUILD -eq 1 ]; then
  buildInventorySuite &
  (runProjectMakeCommand tempo-device-service image) &
  (runProjectMakeCommand food-safety-service build) &
  (runProjectMakeCommand loss-prevention-service build) &
  wait
else
  buildInventorySuite
  runProjectMakeCommand tempo-device-service image
  runProjectMakeCommand food-safety-service build
  runProjectMakeCommand loss-prevention-service build
fi

# Deploy
runProjectMakeCommand inventory-suite deploy
if [ $PARALLEL_BUILD -eq 1 ]; then
  (runProjectMakeCommand food-safety-service deploy) &
  (runProjectMakeCommand loss-prevention-service deploy) &
  applyEdgeXIndex &
  wait
else
  runProjectMakeCommand food-safety-service deploy
  runProjectMakeCommand loss-prevention-service deploy
  applyEdgeXIndex
fi

# Complete
TOTAL_SECONDS=$(( $(date +%s) - ${BEGIN_SECONDS} ))
TZ=UTC logSuccess "%(%H hours %M minutes %S seconds)T" ${TOTAL_SECONDS} |& prefixOutput "setup" "| complete"
logSuccess "${bold}COMPLETED${normal} in ${TOTAL_SECONDS} seconds" |& prefixOutput "setup" "| complete"

exit 0
