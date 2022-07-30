#!/bin/bash

env_file=/mover/.env

function log() {
  echo -e "[$(date '+%Y-%m-%d %T.000')] [MOVER] $1"
}

function init_env_var() {
  if [[ -n $(printenv "$1") ]]; then
    log "Initialized $1=$(printenv "$1")"
    return 0;
  else
    if [[ -n "$2" ]]; then
      log "Variable $1 not set, defaulting to $2";
      export "$1"="$2"
      return 0;
    else
      log "Variable $1 not set, cannot set default value";
      return 1;
    fi
  fi
}

function init_env_var_to_file() {
  if init_env_var "$1" "$2"; then echo -e "$1"="$(printenv "$1")" >> $env_file; return 0; else return 1; fi;
}

function load_env_file() {
  # shellcheck disable=SC2046
  export $(xargs < $env_file)
}

function load_env_var_to_array() {
  readarray -td, "$1" <<<"$(printenv "$2"),"; unset "$1[-1]"; declare -p "$1" > /dev/null 2>&1;
}

function env_var_is_positive() {
  if [[ $(printenv "$1") -gt 0 ]]; then return 0; else return 1; fi
}

function file_exists() {
  if [ -f "$1" ]; then return 0; else return 1; fi
}


