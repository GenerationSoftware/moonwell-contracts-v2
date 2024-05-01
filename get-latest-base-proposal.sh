#!/bin/bash
BASE_DIR="artifacts/foundry"

# Get all base MIP directories
LATEST_MIP_DIR=$(ls -1v ${BASE_DIR}/ | grep '^mip-b' | tail -n 1)

# Get the MIP number from the directory path 
MIP_NUM=${LATEST_MIP_DIR:5:2}

# Print the path to the latest base MIP artifact json file
echo "${BASE_DIR}/${LATEST_MIP_DIR}/mipb${MIP_NUM}.json"
