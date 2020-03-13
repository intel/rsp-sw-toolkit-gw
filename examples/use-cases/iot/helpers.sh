#!/bin/bash

# Apache v2 license
# Copyright (C) <2019> Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

unsupportedFlag() {
  setupColorsAndStyle
  printHelp
  logError "Unsupported flag ${bold}$1"
  exit 1
}

checkAndPrintHelp() {
  if [ ${HELP} -eq 1 ]; then
    printHelp
    printAdditionalHelp
    exit 0
  fi
}

setupColorsAndStyle() {
  # Only define colors if COLOR is enabled (1)
  if [ $COLOR -eq 1 ]; then
      # clear resets color and style back to defaults
      clear="\e[0m"
      # no_color clears the foreground color
      no_color="\e[39m"
      # normal colors
      red="\e[31m"; green="\e[32m"; yellow="\e[33m"; blue="\e[34m"; magenta="\e[35m"; cyan="\e[36m"
      # light colors
      lt_red="\e[91m"; lt_green="\e[92m"; lt_yellow="\e[93m"; lt_blue="\e[94m"; lt_magenta="\e[95m"; lt_cyan="\e[96m"
  fi

  # Only define styles if STYLE is enabled (1):wq
  if [ $STYLE -eq 1 ]; then
      # clear resets color and style back to defaults
      clear="\e[0m"
      # normal clears dim, bold, and underline
      normal="\e[22;24m"
      # styles
      dim="\e[2m"; bold="\e[1m"; uline="\e[4m"
  fi
}

failHard() {
  local project=$1
  shift
  local logFile="${GSG_DIR}/logs/${project/\//_}.log"
  logError "********************************************************************************"
  logError "Error in componenet: ${bold}${project}"
  logError
  logError "$@"
  logError "Check the logs at ${bold}${logFile}"
  logError
  logError "********************************************************************************"
  logError "${bold}Please re-run this script to try again"
  # give a little insight into what it is trying to kill
  set -x
  # this will kill (SIGTERM) the whole process group of the current PID (-$$ instead of just $$)
  # we do this so that all other parallel processes will cancel
  kill -- -$$
  exit 99
}

__rotateFolder() {
    local folder=$1
    local backup_folder=$2
    if [ -d "${folder}" ]; then
      logDebug "Rotating ${folder} to ${backup_folder}"
      rm -rf ${backup_folder}
      mv ${folder} ${backup_folder}
    fi
}

rotateLogFolders() {
    logDebug "Rotating log files..."
    for i in $(seq 1 $((${MAX_LOG_FOLDERS} - 1)) | sort -r); do
      __rotateFolder "$GSG_DIR/logs.$i" "$GSG_DIR/logs.$(($i + 1))"
    done
    __rotateFolder "$GSG_DIR/logs" "$GSG_DIR/logs.1"
    mkdir -p "$GSG_DIR/logs"
}

# Function outputs date in specified format for logging purposes
prettyDate() {
    if [ ! -z $DATE_FORMAT ]; then
      echo "$(date $DATE_FORMAT)"
    else
      echo "$(date +%X)"
    fi
}

prefixOutput() {
  local args="$@"
  tee -a $GSG_DIR/logs/${1/\//_}.log $GSG_DIR/logs/0-combined.log | sed -r "s?^.*?$(tput setaf 6)[$args]$(tput sgr0) \0?g"
}


# Function takes debug message as argument
logDebug () {
    if [ $QUIET -ne 1 ] && [ $DEBUG -eq 1 ]; then
        printf "${dim}[$(prettyDate)] [DEBUG] ${1:-}${clear}\n"
    fi
}

# Function takes info message as argument
logSuccess () {
    local msg=${1:-}
    shift
    if [ $QUIET -ne 1 ]; then
        printf "${dim}[$(prettyDate)]${normal} ${green}[SUCCESS] ${msg}${clear}\n" "$@"
    fi
}

# Function takes info message as argument
logInfo () {
    if [ $QUIET -ne 1 ]; then
        printf "${dim}[$(prettyDate)]${normal} ${blue}[INFO] ${1:-}${clear}\n"
    fi
}

# Function takes warning message as argument
logWarning () {
    if [ $QUIET -ne 1 ]; then
        printf "${dim}[$(prettyDate)]${normal} ${yellow}[WARNING] ${1:-}${clear}\n"
    fi
}

# Function takes error message as argument
logError () {
    if [ $QUIET -ne 1 ]; then
        printf "${dim}[$(prettyDate)]${normal} ${red}[ERROR] ${1:-}${clear}\n"
    fi
}

showUpdateAvailable() {
  msg="
An update is available for this script, would you like to download and run the updated version?


Remote Log:

$(git log HEAD..origin/$(git rev-parse --abbrev-ref HEAD))
"
  whiptail --title "Update Available" \
    --yesno "${msg}" \
    --scrolltext \
    $(stty size)
}

runUpdate() {
  cd $GSG_DIR
  git pull
  IS_RUNNING_UPDATE=1 exec $0 "$@" || exit $? && exit 0
  exit 0
}

checkForScriptUpdates() {
  if [ $SKIP_UPDATE -eq 0 ]; then
    logInfo "Checking for script updates..."
    cd $GSG_DIR
    git fetch origin
    if [ ! -z "$(git status -sb |& head -1 | grep behind)" ]; then
      logInfo "Script update(s) available"
      if [ $IS_RUNNING_UPDATE -eq 1 ]; then
        logWarning "Update detected but we are already attempting to run updated script. Skipping update..."
        exit 0
      fi
      # ask user if they want to update, otherwise continue with existing script path
      if showUpdateAvailable; then
        logInfo "Downloading and running updates..."
        runUpdate "$@"
        exit $?
      else
        logWarning "User declined update"
      fi
    elif [ $IS_RUNNING_UPDATE -eq 1 ]; then
      logSuccess "Running updated script"
    else
      logInfo "No updates available"
    fi
  fi
}

showRootWarning() {
  msg="This script is not intended to be run as the root user. Continue?"
  whiptail --title "Running as root" \
    --yesno "${msg}" \
    $(stty size)
}

warnIfRootUser() {
  if [ $((`id -u`)) -eq 0 ]; then
    logWarning "This script is ${bold}NOT${normal} intended to be run as 'root' or 'sudo'"
    showRootWarning || exit 1
  fi
}

installDependencies() {
  if [ $(type -P make) ] && [ $(type -P curl) ]; then
    logInfo "Dependencies already met"
  else
    logInfo
    logInfo "Installing the following dependencies..."
    logInfo  "    1. make"
    logInfo  "    2. curl"
    logInfo
    sudo apt-get update
    sudo apt-get -y install build-essential curl
  fi
}

checkDependencies() {
  logInfo
  logInfo  "Checking docker and Intel RSP..."
  logInfo
  {
    sudo docker ps -q > /dev/null
  } || {
    logError "Docker is not running. Please make sure Docker is installed."
    exit 1
  }
  logInfo "Docker...OK"
  logInfo
  if curl --output /dev/null --silent --head --fail "http://127.0.0.1:8080/web-admin"
  then
      logInfo "Intel RSP Controller...OK"
  else
      logError
      logError "Intel RSP is not running. Please follow instructions to install and run RSP controller."
      logError
      exit 1
  fi
}

sudoPrompt() {
  logInfo "sudo prompt if required"
  sudo -E printf ""
}


cloneAndUpdateRepo() {
  local project=$1
  shift
  if [ ! -d "$PROJECTS_DIR/${project}" ]; then
      cd $PROJECTS_DIR
      logInfo "Cloning ${project} into $PROJECTS_DIR/${project}..." |& prefixOutput ${project}
      git clone "$@" ${GITHUB_URL}/${GITHUB_ORG}/${REPO_PREFIX}${project}.git ${project} |& prefixOutput ${project} "| git clone"
  fi
  cd $PROJECTS_DIR/${project}
  logInfo "Updating ${project}..." |& prefixOutput ${project}
  git pull |& prefixOutput ${project} "| git pull"
}

updateRepoSubmodules() {
  local project=$1
  cd $PROJECTS_DIR/${project}
  git pull --recurse-submodules |& prefixOutput ${project} "| git pull"
  git submodule sync |& prefixOutput ${project}
  git submodule update --init --recursive |& prefixOutput ${project} "| submodule update"
}

runProjectMakeCommand() {
  local project=$1
  shift
  logDebug "Executing: make $@..." |& prefixOutput ${project}
  (time sudo -E make -C $PROJECTS_DIR/${project} $@ || failHard "${project}" "Error while running '${bold}make $@${normal}' command for ${bold}${project}") |& prefixOutput ${project} "| make ${1:-}"
}

installSecrets() {
  logInfo "Copying secret files..."
  cp $GSG_DIR/secrets/inventory-suite.json $PROJECTS_DIR/inventory-suite/secrets/configuration.json
  cp $GSG_DIR/secrets/demo-ui.json $PROJECTS_DIR/inventory-suite/demo-ui/src/assets/configuration/appConfig.json
  cp $GSG_DIR/secrets/food-safety.json $PROJECTS_DIR/food-safety-service/secrets/configuration.json
  cp $GSG_DIR/secrets/loss-prevention.json $PROJECTS_DIR/loss-prevention-service/secrets/configuration.json
}

buildInventorySuite() {
  logInfo "Building Intel® RSP Inventory Suite..."
  local project=inventory-suite
  cd $PROJECTS_DIR/${project}
  for sub in $(git submodule status | sed -nr 's/ *[a-z0-9]+ *([^ ]+) .*/\1/p'); do
    if [ $PARALLEL_BUILD -eq 1 ]; then
      (PROJECTS_DIR=$PROJECTS_DIR/${project} runProjectMakeCommand "${sub}" -C .. ${sub}) &
    else
      PROJECTS_DIR=$PROJECTS_DIR/${project} runProjectMakeCommand "${sub}" -C .. ${sub}
    fi
  done

  if [ $PARALLEL_BUILD -eq 1 ]; then
    wait
  fi
}

applyEdgeXIndex() {
  logInfo
  logInfo "Applying index to EdgeX's reading collection..."
  local project="inventory-suite"
  EDGEX_INDEX_SLEEP=${EDGEX_INDEX_SLEEP:-5}
  EDGEX_INDEX_RETRY=${EDGEX_INDEX_RETRY:-30}
  i=0
  while [ $i -lt ${EDGEX_INDEX_RETRY} ]; do
      (sudo docker exec -it $(sudo docker ps -qf name=Inventory-Suite-Dev_mongo.1) mongo localhost/coredata --eval "db.reading.createIndex({uuid:1})" || logInfo "mongo exit code: $?") |& prefixOutput "${project}" "| edge-x mongo"
      [ $? -eq 0 ] && break
      logWarning "Unable to apply index to edgex mongo. Trying again in a few seconds."
      sleep ${EDGEX_INDEX_SLEEP}
      i=$((i + 1))
      logWarning "Retry ${i} of ${EDGEX_INDEX_RETRY}..."
  done
  if [ ${EDGEX_INDEX_RETRY} -eq $i ]; then
    failHard "${project}" "Not able to apply index to EdgeX Mongo. Exiting..." |& prefixOutput "${project}" "| edge-x mongo"
  else
   logInfo "EdgeX and Inventory Suite successfully deployed!"
  fi
}

printRSPBanner() {
  local intelColor=${blue}
  local rspColor=${lt_blue}
  local invSuiteColor=${lt_blue}

  printf "${intelColor}
██  ███    ██ ████████ ███████ ██       █ ██████  █    ${rspColor}██████  ███████ ██████${intelColor}
██  ████   ██    ██    ██      ██      █  ██   ██  █   ${rspColor}██   ██ ██      ██   ██${intelColor}
██  ██ ██  ██    ██    █████   ██     █   ██████    █  ${rspColor}██████  ███████ ██████${intelColor}
██  ██  ██ ██    ██    ██      ██      █  ██   ██  █   ${rspColor}██   ██      ██ ██${intelColor}
██  ██   ████    ██    ███████ ███████  █ ██   ██ █    ${rspColor}██   ██ ███████ ██${intelColor}
${invSuiteColor}
██  ███    ██ ██    ██ ███████ ███    ██ ████████  ██████  ██████  ██    ██
██  ████   ██ ██    ██ ██      ████   ██    ██    ██    ██ ██   ██  ██  ██
██  ██ ██  ██ ██    ██ █████   ██ ██  ██    ██    ██    ██ ██████    ████
██  ██  ██ ██  ██  ██  ██      ██  ██ ██    ██    ██    ██ ██   ██    ██
██  ██   ████   ████   ███████ ██   ████    ██     ██████  ██   ██    ██

              ███████ ██    ██  ██ ████████ ███████
              ██      ██    ██  ██    ██    ██
              ███████ ██    ██  ██    ██    █████
                   ██ ██    ██  ██    ██    ██
              ███████  ██████   ██    ██    ███████
${clear}
"
}
