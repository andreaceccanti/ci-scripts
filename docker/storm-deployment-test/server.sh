#!/bin/bash
set -ex

function cleanup(){
  # copy testsuite reports
  docker cp $testsuite_name:/home/tester/storm-testsuite/reports $(pwd) || echo "Cannot copy tests report"

  # copy StoRM logs
  docker cp $deployment_name:/var/log/storm $(pwd) || echo "Cannot copy StoRM logs"

  # get deployment log
  docker logs --tail="all" $deployment_name &> storm-deployment.log || echo "Cannot get the deployment log"

  # remove containers
  docker rm -fv $deployment_name || echo "Cannot remove the deployment container"
  docker rm -fv $testsuite_name || echo "Cannot remove the testsuite container"

  # remove storage files
  rm -rf ${storage_dir} || echo "Cannot remove the storage dir"
}

trap cleanup EXIT

echo "Executing server.sh ..."

MODE=${MODE:-"clean"}
echo "MODE=${MODE}"

PLATFORM=${PLATFORM:-"centos6"}
echo "PLATFORM=${PLATFORM}"

if [ -n "${STORM_REPO}" ]; then
  STORM_REPO=${STORM_REPO}
else
  echo "ERROR: STORM_REPO not found. Please check your environment variables."
  exit 1
fi

DOCKER_REGISTRY_HOST=${DOCKER_REGISTRY_HOST:-""}
echo "DOCKER_REGISTRY_HOST=${DOCKER_REGISTRY_HOST}"

STORAGE_PREFIX=${STORAGE_PREFIX:-"/storage"}
echo "STORAGE_PREFIX=${STORAGE_PREFIX}"

TESTSUITE_BRANCH=${TESTSUITE_BRANCH:-"develop"}
echo "TESTSUITE_BRANCH=${TESTSUITE_BRANCH}"

STORM_DEPLOYMENT_TEST_BRANCH=${STORM_DEPLOYMENT_TEST_BRANCH:-"master"}
echo "STORM_DEPLOYMENT_TEST_BRANCH=${STORM_DEPLOYMENT_TEST_BRANCH}"

if [ -n "${TESTSUITE_EXCLUDE}" ]; then
  EXCLUDE_CLAUSE="-e TESTSUITE_EXCLUDE=${TESTSUITE_EXCLUDE}"
else
  EXCLUDE_CLAUSE="-e TESTSUITE_EXCLUDE=to-be-fixed"
fi

if [ -n "${DOCKER_REGISTRY_HOST}" ]; then
  REGISTRY_PREFIX=${DOCKER_REGISTRY_HOST}/
else
  REGISTRY_PREFIX=""
fi

TEST_ID=$(mktemp -u storm-XXXXXX)

storage_dir=${STORAGE_PREFIX}/$MODE-$PLATFORM-$TEST_ID-storage
gridmap_dir=${STORAGE_PREFIX}/$MODE-$PLATFORM-$TEST_ID-gridmapdir

mkdir -p $storage_dir
mkdir -p $gridmap_dir

# Grab latest images
deployment_image=${REGISTRY_PREFIX}italiangrid/storm-deployment-test:${PLATFORM}
docker pull $deployment_image
testsuite_image=${REGISTRY_PREFIX}italiangrid/storm-testsuite
docker pull $testsuite_image

# run StoRM deployment and get container id
deploy_id=`docker run -d -e "STORM_REPO=${STORM_REPO}" -e "MODE=${MODE}" -e "PLATFORM=${PLATFORM}" \
  -e "STORM_DEPLOYMENT_TEST_BRANCH=${STORM_DEPLOYMENT_TEST_BRANCH}" \
  -h docker-storm.cnaf.infn.it \
  -v $storage_dir:/storage:rw \
  -v $gridmap_dir:/etc/grid-security/gridmapdir:rw \
  -v /etc/localtime:/etc/localtime:ro \
  $deployment_image \
  /bin/sh deploy.sh`

# get names for deployment and testsuite containers
deployment_name=`docker inspect -f "{{ .Name }}" $deploy_id|cut -c2-`
testsuite_name="ts-linked-to-$deployment_name"

# run StoRM testsuite when deployment is over
docker run -e "TESTSUITE_BRANCH=${TESTSUITE_BRANCH}" \
  $EXCLUDE_CLAUSE --link $deployment_name:docker-storm.cnaf.infn.it \
  -v /etc/localtime:/etc/localtime:ro \
  --name $testsuite_name \
  $testsuite_image
