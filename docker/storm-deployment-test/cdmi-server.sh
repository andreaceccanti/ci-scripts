#!/bin/bash
set -ex

function cleanup(){
  # copy testsuite reports
  echo "Copy storm-testsuite reports ..."
  docker cp $testsuite_name:/home/tester/storm-testsuite/reports $(pwd) || echo "Cannot copy tests report"

  # copy StoRM logs
  echo "Copy storm services logs ..."
  docker cp $deployment_name:/var/log/storm $(pwd) || echo "Cannot copy StoRM logs"

  # copy cdmi-server logs
  #echo "Copy cdmi-storm docker logs ... $cdmiserver_name"
  #docker logs --tail="all" $cdmiserver_name &> cdmi-server.log || echo "Cannot get the cdmi-server log"

  # copy redis-server logs
  #echo "Copy redis-server docker logs ... $redis_name"
  #docker logs --tail="all" $redis_name &> redis-server.log || echo "Cannot get the redis-server log"

  # get deployment log
  echo "Copy storm deployment docker logs ... $deployment_name"
  docker logs --tail="all" $deployment_name &> storm-deployment.log || echo "Cannot get the deployment log"

  # stop containers
  echo "Stop container ... $deployment_name"
  docker stop $deployment_name
  #echo "Stop container ... $redis_name"
  #docker stop $redis_name

  # remove containers
  echo "Remove containers ... $deployment_name $testsuite_name $cdmiserver_name $redis_name"
  docker rm -fv $deployment_name || echo "Cannot remove the deployment container"
  docker rm -fv $testsuite_name || echo "Cannot remove the testsuite container"
  #docker rm -fv $cdmiserver_name || echo "Cannot remove the cdmi-server container"
  #docker rm -fv $redis_name || echo "Cannot remove the redis-server container"

}

trap cleanup EXIT

echo "Executing cdmi-server.sh ..."

#if [ -z ${CDMI_CLIENT_SECRET+x} ]; then echo "CDMI_CLIENT_SECRET is unset"; exit 1; fi
#if [ -z ${IAM_USER_PASSWORD+x} ]; then echo "IAM_USER_PASSWORD is unset"; exit 1; fi

CDMI_CLIENT_SECRET=${CDMI_CLIENT_SECRET:-"secret"}
IAM_USER_PASSWORD=${IAM_USER_PASSWORD:-"secret"}

MODE=${MODE:-"clean"}
echo "MODE=${MODE}"

PLATFORM=${PLATFORM:-"centos6"}
echo "PLATFORM=${PLATFORM}"

DOCKER_REGISTRY_HOST=${DOCKER_REGISTRY_HOST:-""}
echo "DOCKER_REGISTRY_HOST=${DOCKER_REGISTRY_HOST}"

STORAGE_PREFIX=${STORAGE_PREFIX:-"/storage"}
echo "STORAGE_PREFIX=${STORAGE_PREFIX}"

STORM_DEPLOYMENT_TEST_BRANCH=${STORM_DEPLOYMENT_TEST_BRANCH:-"master"}
echo "STORM_DEPLOYMENT_TEST_BRANCH=${STORM_DEPLOYMENT_TEST_BRANCH}"

TESTSUITE_BRANCH=${TESTSUITE_BRANCH:-"master"}
echo "TESTSUITE_BRANCH=${TESTSUITE_BRANCH}"

if [ -n "${TESTSUITE_EXCLUDE}" ]; then
  EXCLUDE_CLAUSE="-e TESTSUITE_EXCLUDE=${TESTSUITE_EXCLUDE}"
else
  EXCLUDE_CLAUSE="-e TESTSUITE_EXCLUDE=to-be-fixedORno-btrfsORcdmi"
fi
echo "EXCLUDE_CLAUSE=${EXCLUDE_CLAUSE}"

if [ -n "${DOCKER_REGISTRY_HOST}" ]; then
  REGISTRY_PREFIX=${DOCKER_REGISTRY_HOST}/
else
  REGISTRY_PREFIX=""
fi
echo "REGISTRY_PREFIX=${REGISTRY_PREFIX}"

TEST_ID=$(mktemp -u storm-XXXXXX)

storage_dir=${STORAGE_PREFIX}/$MODE-$PLATFORM-$TEST_ID-storage
gridmap_dir=${STORAGE_PREFIX}/$MODE-$PLATFORM-$TEST_ID-gridmapdir

mkdir -p $storage_dir
mkdir -p $gridmap_dir

# Grab latest images
deployment_image=${REGISTRY_PREFIX}italiangrid/storm-deployment-test:${PLATFORM}
if [ -z "${SKIP_IMAGE_PULL}" ]; then
  docker pull $deployment_image
fi
testsuite_image=${REGISTRY_PREFIX}italiangrid/storm-testsuite
if [ -z "${SKIP_IMAGE_PULL}" ]; then
  docker pull $testsuite_image
fi
#cdmi_image=${REGISTRY_PREFIX}italiangrid/cdmi-storm
#if [ -z "${SKIP_IMAGE_PULL}" ]; then
#docker pull $cdmi_image
#fi

# run StoRM deployment and get container id
deploy_id=`docker run -d -e "MODE=${MODE}" -e "PLATFORM=${PLATFORM}" \
  -e "STORM_DEPLOYMENT_TEST_BRANCH=${STORM_DEPLOYMENT_TEST_BRANCH}" \
  -h docker-storm.cnaf.infn.it \
  -v $storage_dir:/storage:rw \
  -v $gridmap_dir:/etc/grid-security/gridmapdir:rw \
  $deployment_image \
  /bin/sh deploy.sh`

# get names for deployment and testsuite containers
deployment_name=`docker inspect -f "{{ .Name }}" $deploy_id|cut -c2-`
testsuite_name="ts-linked-to-$deployment_name"
#redis_name="redis-linked-to-$deployment_name"
#cdmiserver_name="cdmi-linked-to-$deployment_name"

# run redis server
#docker run -d -h redis.cnaf.infn.it \
#  --link $deployment_name:docker-storm.cnaf.infn.it \
#  --name $redis_name \
#  redis:latest

# run CDMI StoRM
#docker run -d \
#  -e "MODE=${MODE}" \
#  -e "PLATFORM=${PLATFORM}" \
#  -e "STORM_DEPLOYMENT_TEST_BRANCH=${STORM_DEPLOYMENT_TEST_BRANCH}" \
#  -e "CDMI_CLIENT_SECRET=${CDMI_CLIENT_SECRET}" \
#  -e "REDIS_HOSTNAME=redis.cnaf.infn.it" \
#  --name $cdmiserver_name \
#  --link $redis_name:redis.cnaf.infn.it \
#  --link $deployment_name:docker-storm.cnaf.infn.it \
#  -h cdmi-storm.cnaf.infn.it \
#  $cdmi_image

# run StoRM testsuite when deployment is over  WITH LINK TO CDMI
#docker run -e "TESTSUITE_BRANCH=${TESTSUITE_BRANCH}" \
#  -e "CDMI_CLIENT_SECRET=${CDMI_CLIENT_SECRET}" \
#  -e "IAM_USER_PASSWORD=${IAM_USER_PASSWORD}" \
#  $EXCLUDE_CLAUSE \
#  --link $deployment_name:docker-storm.cnaf.infn.it \
#  --link $cdmiserver_name:cdmi-storm.cnaf.infn.it \
#  --name $testsuite_name \
#  $testsuite_image
  

# run StoRM testsuite when deployment is over
docker run -e "TESTSUITE_BRANCH=${TESTSUITE_BRANCH}" \
  -e "CDMI_CLIENT_SECRET=${CDMI_CLIENT_SECRET}" \
  -e "IAM_USER_PASSWORD=${IAM_USER_PASSWORD}" \
  $EXCLUDE_CLAUSE \
  --link $deployment_name:docker-storm.cnaf.infn.it \
  --name $testsuite_name \
  $testsuite_image
