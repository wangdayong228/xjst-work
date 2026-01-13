#!/bin/bash

BLOCKCHAIN_BINARY_PATH=

while getopts "p:" opt; do
  case $opt in
    p)
        BLOCKCHAIN_BINARY_PATH=$OPTARG
        echo "blockchain_binary_path is set:$BLOCKCHAIN_BINARY_PATH"
        ;;
    *)
        echo "$0: invalid option -$OPTARG" >&2
		    echo "Usage: $0 [-p blockchain_binary_path] " >&2
		    exit
		    ;;
  esac
done

#go to dir where the script is as working dir.
SCRIPTPATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
cd $SCRIPTPATH

nohup $BLOCKCHAIN_BINARY_PATH --customized-config customized_config.toml &
cwd=$(pwd)
log_monitor_dir=log_monitor
sys_monitor_dir=sys_monitor
sys_monitor_subdir=sys_monitor/prometheus
chown 472 $cwd/$sys_monitor_dir/grafana -R
chmod a+r $cwd/$sys_monitor_dir/prometheus -R
cd $cwd/$log_monitor_dir && docker-compose up -d
cd $cwd/$sys_monitor_subdir && docker-compose up -d
cd $cwd/$sys_monitor_dir && docker-compose up -d
