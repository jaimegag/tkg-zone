#!/bin/bash -e

CLUSTER_NAME=$1
CLUSTER_CONFIG=$2
NUM_WORKR_NODES=$3

# Create cluster, expected WORKER_MACHINE_COUNT: 0
tanzu cluster create -f $CLUSTER_CONFIG -v 6
# Get auto generated MachineSet name, should have 0 replicas
MACHINE_SET_NAME=`kubectl get machineset -o custom-columns=NAME:.metadata.name | grep $CLUSTER_NAME`
# Duplicate MachineSet creting new one with shortened name (using only the cluster name)
kubectl get machineset $MACHINE_SET_NAME -oyaml | yq '.metadata.name = "'$CLUSTER_NAME'"' | kubectl apply -f -
# Delete old MachineSet
kubectl delete machineset $MACHINE_SET_NAME
# Scale clustere to desired number of nodes
tanzu cluster scale $CLUSTER_NAME -w $NUM_WORKR_NODES