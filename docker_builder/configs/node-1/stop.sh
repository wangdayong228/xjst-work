#!/bin/bash

HOST_P2P_PORT=

while getopts "p:" opt; do
  case $opt in
    p)
        HOST_P2P_PORT=$OPTARG
        echo "host_p2p_port is set:$HOST_P2P_PORT"
        ;;
    *)
        echo "$0: invalid option -$OPTARG" >&2
              echo "Usage: $0 [-p host_p2p_port]" >&2
              exit
              ;;
  esac
done

systemctl stop conflux_$HOST_P2P_PORT

compose_command='docker compose'
if command -v docker-compose &> /dev/null; then
    compose_command='docker-compose'
fi

cwd=$(pwd)
log_monitor_dir=log_monitor
sys_monitor_dir=sys_monitor
sys_monitor_subdir=sys_monitor/prometheus
cd $cwd/$log_monitor_dir && $compose_command down
if ! pgrep conflux_ >/dev/null; then
    cd $cwd/$sys_monitor_subdir && $compose_command down
    cd $cwd/$sys_monitor_dir && $compose_command down
fi
