#!/bin/bash
# Installs MongoDB 7.0 Community on Amazon Linux 2
set -euxo pipefail
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

cat > /etc/yum.repos.d/mongodb-org-7.0.repo <<'EOF'
[mongodb-org-7.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/amazon/2/mongodb-org/7.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://pgp.mongodb.com/server-7.0.asc
EOF

yum install -y mongodb-org

# Listen on the private interface too; access is restricted to the backend
# security group on port 27017 by the VPC security groups.
sed -i 's/^  bindIp: .*/  bindIp: 0.0.0.0/' /etc/mongod.conf

systemctl enable mongod
systemctl start mongod

# Wait until mongod accepts connections
for i in $(seq 1 30); do
  if mongosh --quiet --eval 'db.runCommand({ ping: 1 }).ok' | grep -q 1; then
    echo "mongod is up"
    break
  fi
  sleep 2
done
