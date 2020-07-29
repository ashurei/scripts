#!/bin/bash
#################################################
# Description : Oracle Listener client ip
# Create DATE : 2020.07.29
# Last Update DATE : 2020.07.29 by ashurei
# Copyright (c) Technical Solution, 2020
#################################################

LISTENER=$(ps -ef | grep tnslsnr | grep -v grep | awk '{print $9}')
LISTENER_CNT=$(ps -ef | grep tnslsnr | grep -v grep | wc -l)

# Check Listener Process
if [ "${LISTENER_CNT}" == 0 ]
then
    echo "There is no LISTENER process."
    exit 1
fi

# Check all listeners
for lsnr in ${LISTENER}
do
  OUTPUT="${lsnr}"_client_ip.txt
  date 1> "${OUTPUT}"
  CUR_LOG=$(lsnrctl status "${lsnr}" | awk '/Listener Log File/ {print $4}')
  LOGDIR=$(dirname "${CUR_LOG}")
  LOGFILE=$(ls "${LOGDIR}/*.xml")
  # Check all log*.xml
  for logfile in ${LOGFILE}
  do
    awk -F "ADDRESS=" '/HOST/ {print $2}' "${logfile}" | awk -F "HOST=" '{print $2}' \
    | awk -F ")" '{print $1}' | sort -u | sed '/^$/d' >> "${OUTPUT}"
  done
done
