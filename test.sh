#!/bin/bash

# What we think Docker Hub is running
docker-compose -f docker-compose.test.yml up sut
RESULT=$?
docker-compose -f docker-compose.test.yml down --remove-orphans -v

cat << EOF
# To get a docker environment similar(?) to docker hub's locally, on for example multipass ubuntu 18.04:
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository    "deb [arch=amd64] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable"
sudo apt-get update
apt-cache madison docker-ce
sudo apt-get install docker-ce=18.03.1~ce~3-0~ubuntu
sudo usermod -aG docker multipass
sudo curl -L "https://github.com/docker/compose/releases/download/1.24.1/docker-compose-\$(uname -s)-\$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
EOF

echo "Result: $RESULT"
exit $RESULT
