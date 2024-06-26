#!/bin/bash



DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

maybe_delete_ccloud_environment

CLUSTER_NAME=pg${USER}redshift${TAG}
CLUSTER_NAME=${CLUSTER_NAME//[-._]/}
# getting cluster URL
CLUSTER=$(aws redshift describe-clusters --cluster-identifier $CLUSTER_NAME | jq -r .Clusters[0].Endpoint.Address)

set +e
log "Delete AWS Redshift cluster"
aws redshift delete-cluster --cluster-identifier $CLUSTER_NAME --skip-final-cluster-snapshot
log "Delete security group sg$CLUSTER_NAME"
aws ec2 delete-security-group --group-name sg$CLUSTER_NAME