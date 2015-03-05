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

MODE="${MODE:-clean}"
PLATFORM="${PLATFORM:-SL6}"
STORM_REPO="${STORM_REPO:-http://radiohead.cnaf.infn.it:9999/view/REPOS/job/repo_storm_develop_SL6/lastSuccessfulBuild/artifact/storm_develop_sl6.repo}"
DOCKER_REGISTRY_HOST=${DOCKER_REGISTRY_HOST:-""}
STORAGE_PREFIX=${STORAGE_PREFIX:-/storage}
BRANCH_TESTSUITE="${BRANCH_TESTSUITE:-develop}"

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
docker pull ${REGISTRY_PREFIX}italiangrid/storm-deployment-test
docker pull ${REGISTRY_PREFIX}italiangrid/storm-testsuite

# run StoRM deployment and get container id
deploy_id=`docker run -d -e "STORM_REPO=${STORM_REPO}" -e "MODE=${MODE}" -e "PLATFORM=${PLATFORM}" \
  -h docker-storm.cnaf.infn.it \
  -v $storage_dir:/storage:rw \
  -v $gridmap_dir:/etc/grid-security/gridmapdir:rw \
  -v /etc/localtime:/etc/localtime:ro \
  ${REGISTRY_PREFIX}italiangrid/storm-deployment-test \
  /bin/sh deploy.sh`

# get names for deployment and testsuite containers
deployment_name=`docker inspect -f "{{ .Name }}" $deploy_id|cut -c2-`
testsuite_name="ts-linked-to-$deployment_name"

# run StoRM testsuite when deployment is over
docker run -e "BRANCH_TESTSUITE=${BRANCH_TESTSUITE}" --link $deployment_name:docker-storm.cnaf.infn.it \
  -v /etc/localtime:/etc/localtime:ro \
  --name $testsuite_name \
  ${REGISTRY_PREFIX}italiangrid/storm-testsuite


