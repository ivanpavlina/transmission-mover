#!/bin/bash

name="entrypoint"
source /home/app/utils.sh

log $name "Initializing environment...";
errored=false;

#if ! env_var_is_set CRON; then log $name "CRON env variable is not set"; errored=true; fi;

if [ "$errored" = true ]; then
  log $name "Environment initialization failed >>\n$(env)"
  exit 1;
fi
log $name "Environment initialization ok"

#crontab="""$CRON /home/app/mover.sh"""
crontab="""* * * * * /home/app/mover.sh"""
echo "$crontab" >> /etc/crontabs/root
log $name "Generated crontab [ $crontab ]"

