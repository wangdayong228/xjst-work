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

cwd=$(pwd)
# systemd配置
cat > /usr/lib/systemd/system/conflux_$HOST_P2P_PORT.service << EOF
[Unit]
Description=conflux_$HOST_P2P_PORT server
After=network.service

[Service]
Type=simple
Environment="RUST_BACKTRACE=1"
WorkingDirectory=$cwd
ExecStart=$cwd/conflux_$HOST_P2P_PORT --customized-config $cwd/customized_config.toml
ExecStop=/usr/bin/kill -15 $MAINPID
StandardOutput=null
LimitCPU=infinity
LimitCORE=infinity
LimitMEMLOCK=infinity
LimitNOFILE=65536
LimitNPROC=65536
TasksMax=65535
TimeoutStopSec=30
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# 系统参数优化
if [ `grep -c "net.core.somaxconn" "/etc/sysctl.conf"` -eq '0' ]; then
  echo "net.core.somaxconn=65535" >> /etc/sysctl.conf
else
  sed -i "s/^net.core.somaxconn=.*/net.core.somaxconn=65535/g" /etc/sysctl.conf
fi

if [ `grep -c "net.ipv4.tcp_fin_timeout" "/etc/sysctl.conf"` -eq '0' ]; then
  echo "net.ipv4.tcp_fin_timeout=30" >> /etc/sysctl.conf
else
  sed -i "s/^net.ipv4.tcp_fin_timeout=.*/net.ipv4.tcp_fin_timeout=30/g" /etc/sysctl.conf
fi
sysctl -p

systemctl daemon-reload
systemctl start conflux_$HOST_P2P_PORT

compose_command='docker compose'
if command -v docker-compose &> /dev/null; then
    compose_command='docker-compose'
fi

log_monitor_dir=log_monitor
sys_monitor_dir=sys_monitor
sys_monitor_subdir=sys_monitor/prometheus
chown 472 $cwd/$sys_monitor_dir/grafana -R
chmod a+r $cwd/$sys_monitor_dir/prometheus -R
cd $cwd/$log_monitor_dir && $compose_command up -d
cd $cwd/$sys_monitor_subdir && $compose_command up -d
cd $cwd/$sys_monitor_dir && $compose_command up -d
