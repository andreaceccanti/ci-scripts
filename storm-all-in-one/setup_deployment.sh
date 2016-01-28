#!/bin/bash
set -x
trap "exit 1" TERM
export TOP_PID=$$

terminate() {
      echo $1 && kill -s TERM $TOP_PID
}

[ -n "${JENKINS_SLAVE_PRIVATE_KEY}" ] || terminate "JENKINS_SLAVE_PRIVATE_KEY not set."
[ -n "${REPO_URL}" ] || terminate "REPO_URL not set."
[ -n "${PLATFORM}" ] || terminate "PLATFORM not set."
[ -n "${MODE}" ] || terminate "MODE not set."
[ -n "${MACHINE_HOSTNAME}" ] || terminate "MACHINE_HOSTNAME not set."
[ -n "${EC2_USER}" ] || terminate "EC2_USER not set."

STORM_DEPLOYMENT_TEST_REPO=${STORM_DEPLOYMENT_TEST_REPO:-https://github.com/italiangrid/storm-deployment-test.git}
STORM_DEPLOYMENT_TEST_BRANCH=${STORM_DEPLOYMENT_TEST_BRANCH:-master}
SSH_OPTIONS="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=false -i $JENKINS_SLAVE_PRIVATE_KEY"
STORM_REPO="${REPO_URL}_$(echo $PLATFORM | tr '[:upper:]' '[:lower:]').repo"
STORM_DB_PASSWORD=${STORM_DB_PASSWORD:-}

chmod 400 ${JENKINS_SLAVE_PRIVATE_KEY}

cat << EOF > deploy_storm.sh
dir=$(mktemp -d storm-deployment.XXXX)
cd $dir
git clone $STORM_DEPLOYMENT_TEST_REPO
cd storm-deployment-test
git checkout $STORM_DEPLOYMENT_TEST_BRANCH
export STORM_REPO=${STORM_REPO}
export PATH=$PATH:/sbin:/usr/sbin
chmod +x ./$MODE-deployment_$PLATFORM.sh
STORM_DB_PASSWORD=$STORM_DB_PASSWORD ./$MODE-deployment_$PLATFORM.sh
EOF

scp ${SSH_OPTIONS} deploy_storm.sh ${EC2_USER}@${MACHINE_HOSTNAME}:
[ $? -ne 0 ] && terminate "Error sending deployment script to ${MACHINE_HOSTNAME}"

ssh -tt ${SSH_OPTIONS} ${EC2_USER}@${MACHINE_HOSTNAME} "sudo sh deploy_storm.sh"
[ $? -ne 0 ] && terminate "Deployment test ERROR"

echo "Deployment test success."
