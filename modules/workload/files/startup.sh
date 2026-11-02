#!/bin/bash
# Startup script: installs the Ops Agent (CPU, memory, disk, network and log collection) and the demo app.
# Idempotent: it runs on every boot and just refreshes the files and restarts the services.
set -euo pipefail

MD="http://metadata.google.internal/computeMetadata/v1/instance/attributes"
metadata() {
  curl -fs -H "Metadata-Flavor: Google" "$MD/$1"
}

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y python3 curl

# --- Ops Agent: system metrics + logs ---------------------------------------
if ! dpkg -s google-cloud-ops-agent >/dev/null 2>&1; then
  curl -sS -o /tmp/add-ops-agent-repo.sh https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
  bash /tmp/add-ops-agent-repo.sh --also-install
fi

# Collect the app's JSON request log in addition to the default system logs and metrics.
metadata ops-agent-config > /etc/google-cloud-ops-agent/config.yaml

# --- Demo app ---------------------------------------------------------------
mkdir -p /opt/demo-app /etc/demo-app
metadata app-py > /opt/demo-app/app.py

umask 077
echo "DEMO_TOKEN=$(metadata demo-token)" > /etc/demo-app/env
umask 022

cat > /etc/systemd/system/demo-app.service <<'UNIT'
[Unit]
Description=Demo web app (instrumented for Cloud Monitoring)
After=network-online.target
Wants=network-online.target

[Service]
EnvironmentFile=/etc/demo-app/env
ExecStart=/usr/bin/python3 /opt/demo-app/app.py
DynamicUser=yes
LogsDirectory=demo-app
AmbientCapabilities=CAP_NET_BIND_SERVICE
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable demo-app
systemctl restart demo-app
systemctl restart google-cloud-ops-agent
