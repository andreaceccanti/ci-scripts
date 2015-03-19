#!/bin/bash
set -x

trap "exit 1" TERM
export TOP_PID=$$

terminate() {
  echo $1 && kill -s TERM $TOP_PID
}

## Image, IP, flavour, etc... for VM that will be started
MACHINE_IMAGE=${MACHINE_IMAGE:-CoreOS_Beta}
MACHINE_NAME=${MACHINE_NAME:-cloud-vm178}
MACHINE_HOSTNAME=${MACHINE_NAME}.cloud.cnaf.infn.it
MACHINE_IP=${MACHINE_IP}
MACHINE_KEY_NAME=${MACHINE_KEY_NAME:-jenkins}
MACHINE_FLAVOR=${MACHINE_FLAVOR:-cnaf.medium.plus}
MACHINE_SECGROUPS=${MACHINE_SECGROUPS:-jenkins-slave}

DOCKER_REGISTRY_URL=${DOCKER_REGISTRY_URL:-http://cloud-vm128.cloud.cnaf.infn.it}
DOCKER_REGISTRY_AUTH_TOKEN=${DOCKER_REGISTRY_AUTH_TOKEN}

## nova client environment
export OS_USERNAME=${OS_USERNAME}
export OS_PASSWORD=${OS_PASSWORD}
export OS_TENANT_ID=${OS_TENANT_ID}
export OS_TENANT_NAME=${OS_TENANT_NAME}
export OS_AUTH_URL=${OS_AUTH_URL}

## Other script settings
NO_SERVER_MSG="No server with a name or ID of"
DEL_SLEEP_PERIOD=30
EC2_USER=${EC2_USER:-core}
SSH_OPTIONS="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=false -i $JENKINS_SLAVE_PRIVATE_KEY"
RETRY_COUNT=60

# Change permissions on private key
chmod 400 $JENKINS_SLAVE_PRIVATE_KEY

# Download the cloud-config file
wget --no-check-certificate https://raw.githubusercontent.com/italiangrid/ci-scripts/master/openstack/coreos-cloudinit/user-data.yml -O ./user-data.yml
download_status=$?

if [ ${download_status} -ne 0 ]; then
  echo "Cannot download the config file for setting up the machine, quitting..."
  exit 1
fi

# Substitute the real token for docker registry authentication
sed -i 's@auth": ""@auth": "'${DOCKER_REGISTRY_AUTH_TOKEN}'"@g' ./user-data.yml

# delete running machine
del_output=$(nova delete $MACHINE_NAME)

if [[ "${del_output}" != ${NO_SERVER_MSG}* ]]; then
  if [ -n "${del_output}" ]; then
    echo "Unexpected nova delete output: ${del_output}"
    echo "Continuing..."
  else
    echo "Machine found active. Sleeping for ${DEL_SLEEP_PERIOD} seconds..."
    sleep ${DEL_SLEEP_PERIOD}
  fi
fi

# start the vm and wait until it gets up
nova boot --image ${MACHINE_IMAGE} --flavor ${MACHINE_FLAVOR} --user-data ./user-data.yml --key-name ${MACHINE_KEY_NAME} --security-groups ${MACHINE_SECGROUPS} ${MACHINE_NAME}
boot_status=$?

if [ ${boot_status} -ne 0 ]; then
  echo "Boot command exited with an error, quitting..."
  exit 1
fi

attempts=0
status=$(nova show --minimal ${MACHINE_NAME} | awk '/status/ {print $4}')

while [ x"${status}" != "xACTIVE" ]; do
  attempts=$(($attempts+1))
  if [ $attempts -gt ${RETRY_COUNT} ]; then
    echo "Instance not yet active after 5 minutes, failed"
    exit 1;
  fi
  echo Instance not yet active
  sleep 5
  status=$(nova show --minimal ${MACHINE_NAME} | awk '/status/ {print $4}')
done

# add floating ip and wait until vm is pingable
nova add-floating-ip ${MACHINE_NAME} ${MACHINE_IP}
attempts=0
ping -c 1 ${MACHINE_HOSTNAME}
while [ $? -ne 0 ]; do
  attempts=$(($attempts+1))
  if [ $attempts -gt ${RETRY_COUNT} ]; then
    echo "Instance not yet pingable after 5 minutes, failed"
    exit 1
  fi
  echo Instance not yet pingable
  sleep 5
  ping -c 1 ${MACHINE_HOSTNAME}
done

# wait until sshd is up
attempts=0

ssh_output=$(ssh ${SSH_OPTIONS} ${EC2_USER}@${MACHINE_HOSTNAME} hostname 2>&1)
ssh_status=$?

while [ ${ssh_status} -ne 0 ]; do
  attempts=$(($attempts+1))
  if [ $attempts -gt ${RETRY_COUNT} ]; then
    echo "Instance not yet reachable via ssh after several attempts, quitting!"
    exit 1
  fi
  echo Instance not yet reachable via ssh
  sleep 5
  ssh_output=$(ssh ${SSH_OPTIONS} ${EC2_USER}@${MACHINE_HOSTNAME} hostname 2>&1)
  ssh_status=$?
done

echo "Instance started succesfully."
