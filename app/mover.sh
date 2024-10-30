#!/bin/bash

source /mover/utils.sh
load_env_file
load_env_var_to_array _trackers TRACKERS_TO_TRANSFER
_rsync_files=/tmp/rsync-files

log "Starting run"

local_transmission_root_directory=$(transmission-remote "$TRANSMISSION_LOCAL_HOST":"$TRANSMISSION_LOCAL_PORT" --session-info | \
                                      grep -e "^\s*Download directory:" | awk -F': ' '{print $2}' )
remote_transmission_root_directory=$(transmission-remote "$TRANSMISSION_REMOTE_HOST":"$TRANSMISSION_REMOTE_PORT" --session-info | \
                                      grep -e "^\s*Download directory:" | awk -F': ' '{print $2}' )

if [ -z "$local_transmission_root_directory" ]; then
  log "Could not connect to local transmission $TRANSMISSION_LOCAL_HOST:$TRANSMISSION_LOCAL_PORT! Cannot run.";
  exit 1;
fi
if [ -z "$remote_transmission_root_directory" ]; then
  log "Could not connect to remote transmission $TRANSMISSION_REMOTE_HOST:$TRANSMISSION_REMOTE_PORT! Running locally only.";
fi

# sed removes first and last line which are not torrent torrent_ids
local_torrent_list_raw=$(transmission-remote "$TRANSMISSION_LOCAL_HOST":"$TRANSMISSION_LOCAL_PORT" --list | sed '1d;$d')

oldIFS=$IFS
IFS=$'\n'
for line in $local_torrent_list_raw; do

  # Get torrent data
  torrent_id=$(echo "$line" | awk '{print $1}' )
  percentage=$(echo "$line" | awk '{print $2}' )

  torrent_info=$(transmission-remote "$TRANSMISSION_LOCAL_HOST":"$TRANSMISSION_LOCAL_PORT" --torrent "$torrent_id" --info)
  name=$(echo "$torrent_info" | grep -e "^\s*Name:" | awk -F': ' '{print $2}' )
  state=$(echo "$torrent_info" | grep -e "^\s*State:" | awk -F': ' '{print $2}' )
  size=$(echo "$torrent_info" | grep "Total size:" | awk -F': ' '{print $2}' | awk -F' ' '{print $1,$2}')
  magnet=$(echo "$torrent_info" | grep -e "^\s*Magnet:" | awk -F': ' '{print $2}' )
  hash=$(echo "$torrent_info" | grep -e "^\s*Hash:" | awk -F': ' '{print $2}' )
  torrent_file="$TRANSMISSION_LOCAL_TORRENT_FILE_PATH"/"$hash".torrent;

  # Skip if torrent is stopped or incomplete
  if [ "$state" == "Stopped" ]; then log "DEBUG" "Torrent $name is stopped, not transferring"; continue; fi
  if [ "$percentage" != "100%" ]; then log "DEBUG" "Torrent $name is $percentage complete, not transferring"; continue; fi
  if ! file_exists "$torrent_file"; then log "Torrent $name failed torrent file check, file not found $torrent_file"; continue; fi

  # sed removes first two rows
  torrent_file_list=$(transmission-remote "$TRANSMISSION_LOCAL_HOST":"$TRANSMISSION_LOCAL_PORT" --torrent "$torrent_id" --info-files | sed '1,2d')
  torrent_file_count=$(echo "$torrent_file_list" | wc -l)

  # Check if torrent trackers match at least one requested tracker
  tracker_match=false
  # shellcheck disable=SC2154
  for tracker in "${_trackers[@]}"; do
    if [[ $magnet == *"$tracker"* ]]; then tracker_match=true; break; fi
  done

  if [ $tracker_match = false ]; then
    # Torrent does not have any of the requested trackers, just stop it locally
    transmission-remote "$TRANSMISSION_LOCAL_HOST":"$TRANSMISSION_LOCAL_PORT" --torrent "$torrent_id" --stop;
    log "Torrent $name stopped locally"

  else
    # Torrent has one of requested tracker, start transfer if remote is available
    if [ -z "$remote_transmission_root_directory" ]; then
      log "Skipping transfer of $name, remote transmission not available";
    else
      log "Torrent $name ($size in $torrent_file_count files) [$torrent_file] queued for transfer ..."

      if [ -n "$OVERRIDE_REMOTE_PATH" ]; then
        log "... overriding remote path"
        remote_transmission_root_directory=$OVERRIDE_REMOTE_PATH
      fi

      # Build temp file with list of all torrent files for rsync
      echo > $_rsync_files
      for torrent_file_detail in $torrent_file_list; do
        printf "%s\n" "$(echo "$torrent_file_detail" | awk -F' ' '{ for (i=7; i<=NF;i++) print $i }' | tr '\n' ' ' | sed 's/[[:space:]]*$//')" >> $_rsync_files
      done

      # Rsync files to remote
      log "... transferring from local $local_transmission_root_directory to remote $SSH_REMOTE_USERNAME($SSH_KEY)@$SSH_REMOTE_HOST:$SSH_REMOTE_PORT:$remote_transmission_root_directory ..."
      if ! run_retry 3 /usr/bin/rsync -ar --partial --chmod=F777,D777 --files-from=$_rsync_files "$local_transmission_root_directory" \
           -e "ssh -o StrictHostKeyChecking=no -i $SSH_KEY -p $SSH_REMOTE_PORT" \
           "$SSH_REMOTE_USERNAME"@"$SSH_REMOTE_HOST":"$remote_transmission_root_directory"; then
        log "... rsync errors occurred"
        continue
      fi
      log "... successfully transferred files to remote ..."

      # Add torrent to remote transmission
      if ! run_retry 3 transmission-remote "$TRANSMISSION_REMOTE_HOST":"$TRANSMISSION_REMOTE_PORT" --add "$torrent_file"; then
        log "... failed adding torrent to remote transmission"
        continue
      fi
      log "... successfully added torrent to remote transmission ..."

      if ! transmission-remote "$TRANSMISSION_LOCAL_HOST":"$TRANSMISSION_LOCAL_PORT" --torrent "$torrent_id" --stop; then
        log "... failed stopping torrent on local transmission"
        continue
      fi
      log "... torrent stopped on local transmission"
    fi
  fi
done
export IFS=$oldIFS

rm $_rsync_files > /dev/null 2>&1

log "Run finished"
