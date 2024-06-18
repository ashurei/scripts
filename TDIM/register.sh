#!/bin/bash
########################################################
# Description : Register Alarm rule using TDIM API
# Create DATE : 2024.05.20
# Last Update DATE : 2024.06.18 by ashurei
# Copyright (c) Technical Solution, 2024
########################################################

# Input option
while [ $# -gt 0 ]
do
  case "$1" in
  -n) alarmName=$2
      shift
      shift
      ;;
  -t) tcoreID=$2
      shift
      shift
      ;;
  -f) logObject=$2
      shift
      shift
      ;;
  -s) ipList="$2"
      shift
      shift
      ;;
  * ) shift
      ;;
  esac
done

# Validation check
if [ -z "$alarmName" ]
then
  echo "[ERROR] Need Alarm Name."
  exit 1
fi
if [ -z "$tcoreID" ]
then
  echo "[ERROR] Need tcore_id."
  exit 1
fi
if [ -z "$logObject" ]
then
  echo "[ERROR] Need log file name to monitor."
  exit 1
fi
if [ -z "$ipList" ]
then
  echo "[ERROR] Need searchWord."
  exit 1
fi

# Escape \
#ipList=$(echo "$ipList" | sed 's/\\//g')
#echo "$ipList"

searchWord="sshd.*Accepted password for.* from (?!10.26.11.210 |150.23.15.163 |150.23.15.32 |150.31.135.210 |172.18.218.10 |172.25.7.236 |192.168.4.210 |200.131.121.210 |60.11.8.198 |60.11.8.210 |60.20.101.11 |60.22.64.211 |60.31.64.210 |70.12.231.210 |90.90.90.150 |60.50.37.112 |60.50.37.113 |60.50.37.114 |60.50.37.115 |60.50.37.116 |60.50.37.119 |60.50.37.120 |60.50.37.121 |60.50.37.122 |60.11.33.37 |10.30.24.239 |192.168.55.70 |192.168.226.55 |172.18.71.140 |172.25.156.15 |172.25.180.95 |172.25.19.150 |192.168.152.164 |192.168.152.230 |192.168.237.218 |192.168.55.95 |192.168.57.220 |200.161.121.4 |203.226.245.10 |60.11.30.34 |60.31.59.37 |60.50.76.7 |${ipList} )"
#echo $searchWord

# Excute curl
curl --location --request POST 'http://tcore-private-vip:9000/alarm/v1/alarm-definitions' \
--header 'Content-Type: application/json' \
--data '{"alarmDefinitionId":0,"templateId":0,"alarmName":'"\"${alarmName}\""',"alarmType":"log","alarmGroupId":"","alarmGroupName":"","description":"","useYn":"N","probableCause":"","alarmTarget":{"alarmTargetGroupList":[],"alarmTargetResourceList":[{"targetResourceId":'"\"${tcoreID}\""'}],"alarmTargetExcludeResourceList":[]},"metricAlarmRuleList":null,"logAlarmRuleGradeList":[{"logAlarmRuleId":2640411,"occurRule":"0","occurRuleValue1":"","occurRuleValue2":"sec","occurRuleValue3":null,"releaseRule":"0","releaseRuleValue1":"","releaseRuleValue2":"sec","severity":"CR","logObject":'"\"${logObject}\""',"alarmSound":"Y","logAlarmRuleList":[{"ruleId":0,"searchWord":'"\"${searchWord}\""',"description":"","bracket":"","children":null,"conditionAvg":null,"condition":"Y","conjunction":"and","parent":null,"targetDetail":null,"threshold":null,"fieldIndex":null,"fieldNm":null,"fieldType":null,"predOp":null,"predValue":null,"logCondition":null}],"logFieldSep":null}],"trapAlarmRuleGradeList":null,"useSameOccureReleaseRule":true,"commonOccurReleaseRule":{"occurRule":"0","occurRuleValue1":"","occurRuleValue2":"sec","occurRuleValue3":null,"releaseRule":"0","releaseRuleValue1":"","releaseRuleValue2":"sec","alarmSound":"Y"},"tags":null}'
