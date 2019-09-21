#!/usr/bin/env bash
[ -z "$DEBUG" ] || set -x
set -e

(cd app && mvn -Pjar clean package)
multipass transfer app/target/ystack-demo-app-runner.jar demo-ystack-app:/home/multipass/ystack-demo-app-runner.jar
#multipass exec demo-ystack-app -- sudo apt-get install -y --no-install-recommends openjdk-11-jre-headless
multipass exec demo-ystack-app -- java -jar /home/multipass/ystack-demo-app-runner.jar
