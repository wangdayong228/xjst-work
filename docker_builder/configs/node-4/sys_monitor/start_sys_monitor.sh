#!/bin/bash

HOST_MONITOR_PORT=
CONTAINER_NETWORK=

while getopts "P:n:" opt; do
  case $opt in
    P)
        HOST_MONITOR_PORT=$OPTARG
        echo "listen_port is set:$HOST_MONITOR_PORT" 
		;;
    n)
		CONTAINER_NETWORK=$OPTARG
		echo "container_network is set:$CONTAINER_NETWORK" 
		;;
    *)
        echo "$0: invalid option -$OPTARG" >&2
		echo "Usage: $0 [-P listen_port] [-n container_network]" >&2
		exit
		;;

  esac
done

if [ "$HOST_MONITOR_PORT" ]; then
	sed -i "1c COMPOSE_PROJECT_NAME=$HOST_MONITOR_PORT" .env
	sed -i "2c HOST_MONITOR_PORT=$HOST_MONITOR_PORT" .env
    sed -i "9c \    url: 'baas_monitor_prometheus$HOST_MONITOR_PORT:9090'" ./grafana/datasource/home.yaml
    sed -i "8c \      - targets: ['baas_monitor_exporter$HOST_MONITOR_PORT:9100']" ./prometheus/prometheus.yml	
fi
if [ "$CONTAINER_NETWORK" ]; then
	sed -i "3c CONTAINER_NETWORK=$CONTAINER_NETWORK" .env
fi

docker-compose up -d
