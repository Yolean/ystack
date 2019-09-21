#!/usr/bin/env bash
[ -z "$DEBUG" ] || set -x
set -e

# This example makes use of virtual machines for comparison

#export VM_RESOURCES="-m 4G -d 40G -c 4"
#y-cluster-provision-k3s-multipass

VM_NAME="demo-ystack-app"
VM_RESOURCES="-m 2G -d 10G -c 1"
if ! multipass info "$VM_NAME" 2>/dev/null
then
  multipass launch -n "$VM_NAME" $VM_RESOURCES
fi

cat EOF <<
# shell
sudo apt-get update
sudo apt-get install -y --no-install-recommends openjdk-11-jre-headless
sudo apt-get remove -y openjdk-11-jre-headless
EOF

VM_NAME="demo-ystack-db"
VM_RESOURCES="-m 2G -d 10G -c 1"
if ! multipass info "$VM_NAME" 2>/dev/null
then
  multipass launch -n "$VM_NAME" $VM_RESOURCES
fi

# https://neo4j.com/docs/operations-manual/current/installation/linux/debian/
cat EOF <<
# shell
sudo apt-get update
sudo apt-get install -y openjdk-8-jre-headless # Note the version requirement for Neo4j
wget -O - https://debian.neo4j.org/neotechnology.gpg.key | sudo apt-key add -
echo 'deb https://debian.neo4j.org/repo stable/' | sudo tee -a /etc/apt/sources.list.d/neo4j.list
sudo apt-get update
echo "neo4j-enterprise neo4j/question select I ACCEPT" | sudo debconf-set-selections
echo "neo4j-enterprise neo4j/license note" | sudo debconf-set-selections
sudo apt-get install -y neo4j=1:3.5.9
EOF

echo "You'll also need: VM_RESOURCES='-m 4G -d 20G -c 4' y-cluster-provision-k3s-multipass"
