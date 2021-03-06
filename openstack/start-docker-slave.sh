#!/bin/bash
set -x

trap "exit 1" TERM
export TOP_PID=$$

terminate() {
  echo $1 && kill -s TERM $TOP_PID
}

## Image, IP, flavour, etc... for VM that will be started
MACHINE_IMAGE=${MACHINE_IMAGE:-CoreOS_1010.5.0}
MACHINE_NAME=${MACHINE_NAME:-unset}
MACHINE_HOSTNAME=${MACHINE_NAME}.cloud.cnaf.infn.it
MACHINE_IP=${MACHINE_IP}
MACHINE_KEY_NAME=${MACHINE_KEY_NAME:-jenkins}
MACHINE_FLAVOR=${MACHINE_FLAVOR:-cnaf.medium.plus}
MACHINE_SECGROUPS=${MACHINE_SECGROUPS:-jenkins-slave}
EC2_USER=${EC2_USER:-core}

## Cinder volume stuff
VOLUME_NAME=${VOLUME_NAME:-${MACHINE_NAME}-volume}
VOLUME_SIZE=${VOLUME_SIZE:-120}

## CoreOS cloudinit 
USER_DATA_FILE_PATH=${USER_DATA_FILE_PATH:-openstack/coreos-cloudinit/jenkins-slave-nobtrfs.yml}

## Docker registry stuff
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
SSH_OPTIONS="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=false -i $JENKINS_SLAVE_PRIVATE_KEY"
RETRY_COUNT=60

# Change permissions on private key
chmod 400 $JENKINS_SLAVE_PRIVATE_KEY

# Get new cluster id from coreos
cluster_id=$(curl -w "\n" 'https://discovery.etcd.io/new?size=1')

# Substitute the real token for docker registry authentication
sed 's@auth": ""@auth": "'${DOCKER_REGISTRY_AUTH_TOKEN}'"@g' ${USER_DATA_FILE_PATH} > /tmp/userdata

# Substitute cluster id 
sed -i -e 's#@@DISCOVERY_URL@@#'"${cluster_id}"'#' /tmp/userdata

USER_DATA_FILE_PATH=/tmp/userdata

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

# Support for mounting cinder volumes
mount_volume_opts=""

if [[ -n ${MOUNT_VOLUME} ]]; then
  # Delete volume if exists
  cinder delete ${VOLUME_NAME} || echo "Cinder volume ${VOLUME_NAME} does not exist (or there was an error)"

  # Create a brand new one
  cinder create --display-name ${VOLUME_NAME} ${VOLUME_SIZE}
  volume_id=$(cinder show ${VOLUME_NAME} | grep -E '\<id\>' | awk '{print $4}')
  mount_volume_opts="--block-device source=volume,id=${volume_id},dest=volume,shutdown=preserve"
fi

# start the vm and wait until it gets up
nova boot --config-drive true --image ${MACHINE_IMAGE} --flavor ${MACHINE_FLAVOR} --user-data ${USER_DATA_FILE_PATH} \
  --key-name ${MACHINE_KEY_NAME} --security-groups ${MACHINE_SECGROUPS} \
  ${mount_volume_opts} ${MACHINE_NAME}

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
