#!/bin/bash

function log() {
  echo -e "[$(date '+%Y-%m-%d %T.000')] [MOVER] $1"
}

TRACKERS=("iptorrents.com" "ssl.empirehost.me" "hd-space.pw" "announce.partis.si" "tracker.openbittorrent.com") # TODO arr from env

TRANSMISSION_LOCAL_HOST=localhost
TRANSMISSION_LOCAL_PORT=9091

TRANSMISSION_REMOTE_HOST="192.168.200.250"
TRANSMISSION_REMOTE_PORT=9091
SSH_REMOTE_HOST="192.168.200.250"
SSH_REMOTE_PORT=22
SSH_REMOTE_USERNAME="root"
SSH_KEY="/keys/id_rsa"

_FILE_LIST=/tmp/rsync-files

_TRANSMISSION_LOCAL_TORRENT_FILE_PATH=/config/torrents

log "Starting"

local_transmission_root_directory=$(transmission-remote $TRANSMISSION_LOCAL_HOST:$TRANSMISSION_LOCAL_PORT --session-info | \
                                      grep -e "^\s*Download directory:" | awk -F': ' '{print $2}' )
remote_transmission_root_directory=$(transmission-remote $TRANSMISSION_REMOTE_HOST:$TRANSMISSION_REMOTE_PORT --session-info | \
                                      grep -e "^\s*Download directory:" | awk -F': ' '{print $2}' )

if [ -z "$local_transmission_root_directory" ]; then log "Could not determine local root directory!!!"; exit 1; fi
if [ -z "$remote_transmission_root_directory" ]; then log "Could not determine remote root directory!!!"; exit 1; fi

log "Both transmissions initialized: local>$local_transmission_root_directory remote>$remote_transmission_root_directory"

# sed removes first and last line which are not torrent torrent_ids
local_torrent_list_raw=$(transmission-remote $TRANSMISSION_LOCAL_HOST:$TRANSMISSION_LOCAL_PORT --list | sed '1d;$d')

oldIFS=$IFS
IFS=$'\n'
for line in $local_torrent_list_raw; do

  # Get torrent data
  torrent_id=$(echo "$line" | awk '{print $1}' )
  percentage=$(echo "$line" | awk '{print $2}' )

  torrent_info=$(transmission-remote $TRANSMISSION_LOCAL_HOST:$TRANSMISSION_LOCAL_PORT --torrent "$torrent_id" --info)
  name=$(echo "$torrent_info" | grep -e "^\s*Name:" | awk -F': ' '{print $2}' )
  state=$(echo "$torrent_info" | grep -e "^\s*State:" | awk -F': ' '{print $2}' )
  size=$(echo "$torrent_info" | grep "Total size:" | awk -F': ' '{print $2}' | awk -F' ' '{print $1,$2}')
  hash=$(echo "$torrent_info" | grep -e "^\s*Hash:" | awk -F': ' '{print $2}' )
  magnet_link=$(echo "$torrent_info" | grep -e "^\s*Magnet:" | awk -F': ' '{print $2}' )

  # Skip if torrent is stopped or incomplete
  if [ "$state" == "Stopped" ]; then log "Torrent [$name] is stopped, not transferring"; continue; fi
  if [ "$percentage" != "100%" ]; then log "Torrent [$name] $percentage complete, not transferring"; continue; fi

  # sed removes first two rows
  torrent_file_list=$(transmission-remote $TRANSMISSION_LOCAL_HOST:$TRANSMISSION_LOCAL_PORT --torrent "$torrent_id" --info-files | sed '1,2d')
  torrent_file_count=$(echo "$torrent_file_list" | wc -l)

  # Check if torrent trackers match at least one requested tracker
  tracker_match=false
  for tracker in "${TRACKERS[@]}"; do
    if [[ $magnet_link == *"$tracker"* ]]; then tracker_match=true; break; fi
  done

  log "Torrent ($torrent_id) $name queued for transfer. $size in $torrent_file_count files"

  stop_local_torrent=true

  # Torrent has one of requested tracker, start transfer
  if [ $tracker_match = true ]; then
    log "Transferring torrent to remote"

    # Build temp file with list of all torrent files for rsync
    echo > $_FILE_LIST
    for torrent_file_detail in $torrent_file_list; do
      printf "%s\n" "$(echo "$torrent_file_detail" | awk -F' ' '{ for (i=7; i<=NF;i++) print $i }' | tr '\n' ' ' | sed 's/[[:space:]]*$//')" >> $_FILE_LIST
    done

    # Rsync files
    if /usr/bin/rsync -ar --partial --files-from=$_FILE_LIST "$local_transmission_root_directory" \
       -e "ssh -o StrictHostKeyChecking=no -i $SSH_KEY" \
       "$SSH_REMOTE_USERNAME"@"$SSH_REMOTE_HOST":"$remote_transmission_root_directory"; then

      log "Rsync succeeded, setting permissions on remote...NOT FOR NOW"
      #ssh -i "$SSH_KEY" "$SSH_REMOTE_USERNAME"@"$SSH_REMOTE_HOST"  "$remote_transmission_root_directory"
      #log "Permissions set, adding torrent to remote transmission"

      # Add torrent to remote transmission
      torrent_file="$_TRANSMISSION_LOCAL_TORRENT_FILE_PATH"/"$hash".torrent;
      if transmission-remote "$TRANSMISSION_REMOTE_HOST":"$TRANSMISSION_REMOTE_PORT" --add "$torrent_file"; then
        log "Added torrent to remote transmission successfully"
      else
        # TODO retry
        log "Failed adding torrent to remote transmission"
        stop_local_torrent=false
      fi

    else
      # TODO retry
       log "Rsync errors occurred, will not stop torrent locally"
       stop_local_torrent=false
    fi
  fi

  # Stop torrent if trackers not matched or successfully transferred to remote
  if [ $stop_local_torrent = true ]; then
    transmission-remote "$TRANSMISSION_LOCAL_HOST":"$TRANSMISSION_LOCAL_PORT" --torrent "$torrent_id" --stop;
    log "Torrent stopped locally"
  fi
done
export IFS=$oldIFS

rm $_FILE_LIST > /dev/null 2>&1

log "Done"
