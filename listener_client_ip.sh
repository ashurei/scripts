#!/bin/bash
# 2020.07.29 Created by ashurei
LISTENER=$(ps -ef | grep tnslsnr | grep -v grep | awk '{print $9}')
if [ -z "${LISTENER}" ]
then
    echo "There is no LISTENER process."
    exit 1
fi

LOGFILE=$(lsnrctl status "${LISTENER}" | awk '/Listener Log File/ {print $4}')
awk -F "host_addr=" '/host_addr/ {print $2}' "${LOGFILE}" | awk -F "'" '{print $2}' | sort -u > listener_client_ip.txt
