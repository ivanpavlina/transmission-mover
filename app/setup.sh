#!/bin/bash

source /mover/utils.sh

if file_exists mover-initialized; then exit 0; fi
touch mover-initialized;

log "Initializing environment...";
errored=false;

if ! init_env_var CRON; then errored=true; fi;

if ! init_env_var_to_file TRACKERS_TO_TRANSFER; then errored=true; fi;
if ! init_env_var_to_file TRANSMISSION_REMOTE_HOST; then errored=true; fi;
if ! init_env_var_to_file TRANSMISSION_REMOTE_PORT; then errored=true; fi;
if ! env_var_is_positive TRANSMISSION_REMOTE_PORT; then
  log "TRANSMISSION_REMOTE_PORT env variable invalid, must be a positive integer";
  errored=true;
fi

if ! init_env_var_to_file TRANSMISSION_LOCAL_TORRENT_FILE_PATH "/config/torrents"; then errored=true; fi;
if ! init_env_var_to_file TRANSMISSION_LOCAL_HOST "localhost"; then errored=true; fi;
if ! init_env_var_to_file TRANSMISSION_LOCAL_PORT 9091; then errored=true; fi;

if ! init_env_var_to_file SSH_REMOTE_USERNAME; then errored=true; fi;
if ! init_env_var_to_file SSH_REMOTE_HOST "$TRANSMISSION_REMOTE_HOST"; then errored=true; fi;
if ! init_env_var_to_file SSH_REMOTE_PORT 22; then errored=true; fi;
if ! env_var_is_positive SSH_REMOTE_PORT; then
  log "SSH_REMOTE_PORT env variable invalid, must be a positive integer";
  errored=true;
fi

if ! init_env_var_to_file SSH_KEY "/config/id_rsa"; then errored=true; fi;
if ! file_exists "$SSH_KEY"; then log "No ssh private key found on path $SSH_KEY"; errored=true; else chmod 600 "$SSH_KEY"; fi;

if [ "$errored" = true ]; then log "Environment initialization failed, cannot setup mover!"; env; exit 1; fi
log "Environment initialization ok"

crontab="""$CRON /mover/mover.sh"""
echo "$crontab" >> /etc/crontabs/root
touch /etc/crontabs/cron.update
log  "Generated crontab [ $crontab ]"
