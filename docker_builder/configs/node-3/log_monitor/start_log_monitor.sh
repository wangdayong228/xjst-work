#!/bin/bash

HOST_LOG_PATH=
HOST_WEB_PORT=
CONTAINER_NETWORK=

while getopts "p:P:n:" opt; do
  case $opt in
    p)
        HOST_LOG_PATH=$OPTARG
        echo "log_path is set:$HOST_LOG_PATH" ;;
    P)
        HOST_WEB_PORT=$OPTARG
        echo "listen_port is set:$HOST_WEB_PORT" ;;
    n)
		CONTAINER_NETWORK=$OPTARG
		echo "container_network is set:$CONTAINER_NETWORK" ;;
    *)
        echo "$0: invalid option -$OPTARG" >&2
		echo "Usage: $0 [-p log_path] [-P listen_port] [-n container_network]" >&2
		exit
		;;

  esac
done

if [ "$HOST_WEB_PORT" ]; then
	sed -i "1c COMPOSE_PROJECT_NAME=$HOST_WEB_PORT" .env
	sed -i "3c HOST_WEB_PORT=$HOST_WEB_PORT" .env
fi
if [ "$HOST_LOG_PATH" ]; then
	sed -i "2c HOST_LOG_PATH=$HOST_LOG_PATH" .env
fi
if [ "$CONTAINER_NETWORK" ]; then
	sed -i "4c CONTAINER_NETWORK=$CONTAINER_NETWORK" .env
fi

docker-compose up -d
