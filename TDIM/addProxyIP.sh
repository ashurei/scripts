#!/bin/bash
########################################################
# Description : TDIM add proxy IP to inventory.
# Create DATE : 2026.09.28
# Last Update DATE : 2026.09.28 by ashurei
# Copyright (c) Technical Solution, 2026
########################################################

### Check resource_id file.
if [[ -z "$1" || ! -f "$1" ]]
then
  echo "Give me resource_id file."
  echo "ex) 101,102,103"
  exit 1
fi

### Check proxy IP.
if [ -z "$2" ]
then
  echo "Need proxy IP."
  exit 1
fi

LIST=$(cat "$1")
PROXY="$2"

for resource_id in ${LIST}
do
  # Remove space
  resource_id="${resource_id//[[:space:]]/}"
  [ -z "$resource_id" ] && continue
  YML="/home/tcore/sw/ansible/inventories/${resource_id}/hosts.yml"

  echo "=============================================="
  echo "resource_id: ${resource_id}"
  echo "hosts.yml  : ${YML}"
  echo "Proxy IP   : ${PROXY}"

  if [ ! -f "$YML" ]
  then
    echo "[ERROR]: ${YML} does not exist."
    continue
  fi

  PROXY_LINE="      ansible_ssh_common_args: -o ProxyCommand=\"ssh -i /home/tcore/tcore_dist/ansible/.ssh/id_rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p ${PROXY}\""
  echo $PROXY_LINE

  if grep -q 'ansible_ssh_common_args:' "$YML"
  then
    sed -i "s|^[[:space:]]*ansible_ssh_common_args:.*|${PROXY_LINE}|" "$YML"
  else
    printf '%s\n' "$PROXY_LINE" >> "$YML"
  fi

  curl --request PUT \
    --url http://tcore-private-vip:9000/orchestration/v1/collector/agent/config-change/"${resource_id}" \
    --header 'authflag: SUPER-ADMIN' \
    --header 'loginid: admin'
done
