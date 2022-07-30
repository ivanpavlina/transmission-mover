#!/bin/bash

function log() {
  prefix=""
  message=$1
  if [ $# -eq 3 ]; then prefix="[$1 $2] "; message=$3; fi
  if [ $# -eq 2 ]; then prefix="[$1] "; message=$2; fi

  echo -e "$(date -u) $prefix$message"
}

function env_var_is_set() {
  if [[ ! -z `printenv $1` ]]; then return 0; else return 1; fi
}

function env_var_is_positive() {
  if [[ `printenv $1` -gt 0 ]]; then return 0; else return 1; fi
}

function file_exists() {
  if [ -f "$1" ]; then return 0; else return 1; fi
}

function function_exists() {
  declare -F "$1" > /dev/null;
  return $?
}
