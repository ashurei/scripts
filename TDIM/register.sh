#!/bin/bash
########################################################
# Description : Register Alarm rule using TDIM API
# Create DATE : 2024.05.20
# Last Update DATE : 2024.06.25 by ashurei
# Copyright (c) Technical Solution, 2024
########################################################

# Version: 2024.06.25.r1
# Input option
while [ $# -gt 0 ]
do
  case "$1" in
  -n) alarmName=$2
      shift
      shift
      ;;
  -g) alarmGroupID="$2"
      shift
      shift
      ;;
  -f) logObject=$2
      shift
      shift
      ;;
  -t) tcoreID=$2
      shift
      shift
      ;;
  -s) ipList="$2"
      shift
      shift
      ;;
  -o) osType="$2"
      shift
      shift
      ;;
  -h) echo "usage) ./register.sh -n [alarmName]"
      echo "                     -g [alarmGroupID]"
      echo "                     -f [log file name]"
      echo "                     -t [tcoreID]"
      echo "                     -s [IP list]"
      exit 0
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
#if [ -z "$tcoreID" ]
#then
#  echo "[ERROR] Need tcore_id."
#  exit 1
#fi
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

if [ -n "$tcoreID" ]
then
  tcoreID="{\"targetResourceId\":\"${tcoreID}\"}"
fi

### Create search word with IP.
if [ "$osType" == 'sle' ]
then
  searchWord="(?!${ipList}) terminal=ssh res=success"
elif [[ "$osType" == 'deb' || "$osType" == 'red' || "$osType" == 'red' || "$osType" == 'cen' || "$osType" == 'roc' ]]
then
  searchWord="sshd.*Accepted password for.* from (?!${ipList} )"
else
  echo "[ERROR] OS type is wrong."
  exit 1
fi
#echo $searchWord

# Excute curl
curl --location --request POST 'http://tcore-private-vip:9000/alarm/v1/alarm-definitions' \
--header 'Content-Type: application/json' \
--data '{"alarmDefinitionId":0,"templateId":0,"alarmName":'"\"${alarmName}\""',"alarmType":"log","alarmGroupId":'"\"${alarmGroupID}\""',"alarmGroupName":"비인가","description":"","useYn":"N","probableCause":"","alarmTarget":{"alarmTargetGroupList":[],"alarmTargetResourceList":['"${tcoreID}"'],"alarmTargetExcludeResourceList":[]},"metricAlarmRuleList":null,"logAlarmRuleGradeList":[{"logAlarmRuleId":2640411,"occurRule":"0","occurRuleValue1":"","occurRuleValue2":"sec","occurRuleValue3":null,"releaseRule":"0","releaseRuleValue1":"","releaseRuleValue2":"sec","severity":"CR","logObject":'"\"${logObject}\""',"alarmSound":"Y","logAlarmRuleList":[{"ruleId":0,"searchWord":'"\"${searchWord}\""',"description":"","bracket":"","children":null,"conditionAvg":null,"condition":"Y","conjunction":"and","parent":null,"targetDetail":null,"threshold":null,"fieldIndex":null,"fieldNm":null,"fieldType":null,"predOp":null,"predValue":null,"logCondition":null}],"logFieldSep":null}],"trapAlarmRuleGradeList":null,"useSameOccureReleaseRule":true,"commonOccurReleaseRule":{"occurRule":"0","occurRuleValue1":"","occurRuleValue2":"sec","occurRuleValue3":null,"releaseRule":"0","releaseRuleValue1":"","releaseRuleValue2":"sec","alarmSound":"Y"},"tags":null}'
