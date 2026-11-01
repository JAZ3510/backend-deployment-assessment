#!/bin/bash
# Installs Docker, Docker Compose (v2 plugin) and git on Amazon Linux 2
set -euxo pipefail
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

yum update -y
yum install -y docker git

systemctl enable docker
systemctl start docker

# Let ec2-user run docker without sudo (takes effect on next login)
usermod -aG docker ec2-user

# Docker Compose v2 as a CLI plugin (provides `docker compose`)
COMPOSE_VERSION="v2.29.7"
mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Optional: standalone `docker-compose` command as well
ln -sf /usr/local/lib/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose

docker --version
docker compose version
