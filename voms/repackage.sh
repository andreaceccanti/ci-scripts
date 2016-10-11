#!/bin/bash
set -x
trap "exit 1" TERM
export TOP_PID=$$

terminate() {
      echo $1 && kill -s TERM $TOP_PID
}

[[ -n "${MOCK_HOSTNAME}" ]] || terminate "MOCK_HOSTNAME not set."
[[ -n "${MOCK_USER}" ]] || terminate "MOCK_USER not set."
[[ -n "${VOMS_SRPM_DIR}" ]] || terminate "VOMS_SRPM_DIR not set."
[[ -n "${MOCK_CONFIG}" ]] || terminate "MOCK_CONFIG not set."

SSH_OPTIONS="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=false"

VOMS_REPACKAGE_DIR=voms-repackage/${BUILD_TAG}

ssh ${SSH_OPTIONS} ${MOCK_USER}@${MOCK_HOSTNAME} "mkdir -p ${VOMS_REPACKAGE_DIR}"
[ $? -ne 0 ] && terminate "Error creating repackaging folder" 

scp ${SSH_OPTIONS} ${VOMS_SRPM_DIR}/*.src.rpm ${MOCK_USER}@${MOCK_HOSTNAME}:'~'/${VOMS_REPACKAGE_DIR}/
[ $? -ne 0 ] && terminate "Error uploading source RPMs." 

ssh ${SSH_OPTIONS} ${MOCK_USER}@${MOCK_HOSTNAME} \
      "mock -r ${MOCK_CONFIG} rebuild ${VOMS_REPACKAGE_DIR}/*.src.rpm"

retval=$?
[[ ${retval} -ne 0 ]] && terminate "Error running mock repackaging"

mkdir artifacts

scp ${SSH_OPTIONS} ${MOCK_USER}@${MOCK_HOSTNAME}:/var/lib/mock/${MOCK_CONFIG}/result/*.rpm artifacts

retval=$?
[[ ${retval} -ne 0 ]] && terminate "Error copying back generated artifacts"

echo "Repackage terminated succesfully"
