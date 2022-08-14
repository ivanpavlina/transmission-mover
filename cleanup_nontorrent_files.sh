#!/bin/bash

oldIFS=$IFS
IFS=$'\n'

remote_transmission_root_directory=$(/opt/bin/transmission-remote --session-info | grep -e "^\s*Download directory:" | awk -F': ' '{print $2}' )
torrent_list=$(/opt/bin/transmission-remote --list | sed '1d;$d')
echo "Initialized. Transmission root directory: [$remote_transmission_root_directory]"

echo
echo "Checking for extra files on disk compared to file list from torrent"
for line in $torrent_list; do
  torrent_id=$(echo "$line" | awk '{print $1}' );
  torrent_name=$(echo "$line" | tr -s " " | cut -d ' ' -f 11-);
  percentage=$(echo "$line" | awk '{print $2}');
  if [ "$percentage" != "100%" ]; then echo "Skipping incomplete torrent $torrent_name"; continue; fi;

  printf "%s;;; " "$torrent_name";

  # Build list of files loaded from torrent
  torrent_list_files_raw=$(/opt/bin/transmission-remote --torrent "$torrent_id" --info-files | sed '1,2d')
  torrent_list_files=""
  for torrent_file_line in $torrent_list_files_raw; do
    torrent_list_files=$(printf "%s\n%s" "$torrent_list_files" "$(echo "$torrent_file_line" | awk -F' ' '{ for (i=7; i<=NF;i++) print $i }' | tr '\n' ' ' | sed 's/[[:space:]]*$//')");
  done
  torrent_list_files=$(echo -e "$torrent_list_files" | tac | head -c -1 |tac)
  torrent_list_files_count=$(echo "$torrent_list_files" | wc -l)

  # Build list of files on disk for this torrent
  torrent_folder=$remote_transmission_root_directory/$torrent_name
  torrent_real_files=$(find "$torrent_folder" -type f)
  torrent_real_files_count=$(echo "$torrent_real_files" | wc -l)

  if [ "$torrent_real_files_count" = "$torrent_list_files_count" ]; then
    echo "OK file count";
  elif [ "$torrent_list_files_count" -gt "$torrent_real_files_count" ]; then
      echo "FAILED missing files on disk! This should not happen";
  elif [ "$torrent_real_files_count" -gt "$torrent_list_files_count" ]; then
    echo "EXTRA files found"

    for torrent_real_file in $torrent_real_files; do
      printf "%s>>> " "$torrent_real_file";
      # Remove full path prefix
      torrent_real_file=${torrent_real_file#"$remote_transmission_root_directory/"}

      matched=false
      for torrent_list_file in $torrent_list_files; do
        if [ "$torrent_list_file" = "$torrent_real_file" ]; then
          echo "MATCHED with torrent $torrent_name"
          matched=true
          break
        fi
      done
      if [ $matched = false ]; then
        echo "FAILED this file does not belong to torrent $torrent_name";
      fi
    done
  fi
done

echo
echo "Matching directories (or only one file) on disk to torrents..."
remote_root_file_list=$(find "$remote_transmission_root_directory" -maxdepth 1)
for line in $remote_root_file_list; do
  # Skip root dir
  if [ "$line" = "$remote_transmission_root_directory" ]; then continue; fi;

  matched=false;
  printf "%s::: " "$line"

  for torrent in $torrent_list; do
    # shellcheck disable=SC2086
    torrent_name=$(echo $torrent | tr -s " " | cut -d ' ' -f 11-);
    torrent_location="$remote_transmission_root_directory/$torrent_name";

    if [ "$torrent_location" = "$line" ]; then
      matched=true;
      echo "MATCHED with torrent $torrent_name"
      break;
    fi
  done

  if [ $matched = false ]; then
    echo "FAILED matching with any torrent" ;
  fi
done

export IFS=$oldIFS
