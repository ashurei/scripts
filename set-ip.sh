#!/bin/bash
########################################################
# Description : Set IP address (RHEL 8)
# Create DATE : 2025.05.14
# Last Update DATE : 2025.05.14 by ashurei
# Copyright (c) Technical Solution, 2025
########################################################

### Version: 2025.05.14.r1

# ======================================================================================= #
### Input option
while [ $# -gt 0 ]
do
  case "$1" in
  -d) devName="$2"
      shift
      shift
      ;;
  -i) ipAddress="$2"
      shift
      shift
      ;;
  -g) gateWay="$2"
      shift
      shift
      ;;
  -b) bondName="$2"
      shift
      shift
      ;;
  -s1) slaveDev1="$2"
      shift
      shift
      ;;
  -s2) slaveDev2="$2"
      shift
      shift
      ;;
  -h) echo "usage) ./set_ip.sh -d [devName]"
      echo "                   -i [ipAddress]"
      echo "                   -g [gateWay]"
      echo "                   -b [isBond(y/n)]"
      echo "                   -s [IP list]"
      exit 0
      ;;
  * ) shift
      ;;
  esac
done

# ======================================================================================= #
### Validation check
if [[ -z "$bondName" && -z "$devName" ]]   # if no bonding && no device name
then
  echo "[ERROR] Need device name."
  exit 1
fi

# IP address
if [ -z "$ipAddress" ]
then
  echo "[ERROR] Need IP address to set."
  exit 1
else
  if [[ "$ipAddress" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[1-2][0-9]|3[0-2])$ ]]
  then
    echo "IP address is VALID."
  else
    echo "IP address is INVALID. (ex. 10.10.10.10/24)"
    exit 1
  fi
fi

# Gateway
if [ -n "$gateWay" ]
then
  if [[ "$gateWay" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
  then
    echo "Gateway address is VALID."
  else
    echo "Gateway address is INVALID. (ex. 10.10.10.10)"
    exit 1
  fi
fi

# ======================================================================================= #
### Set variable
OS_MAJOR=$(grep VERSION_ID /etc/os-release | sed 's/\"//g' | cut -d'=' -f2 | cut -d'.' -f1)
#echo $OS_MAJOR

### RHEL 8, Rocky 8
if [ "$OS_MAJOR" == 8 ]
then
  if [ -n "$bondName" ]
  then
    if [[ -z "$slaveDev1" || -z "$slaveDev2" ]]
    then
      echo "[ERROR] Need two slave device name."
      exit 1
    fi
    #echo $bondName
    #echo $slaveDev1
    #echo $slaveDev2

    # Create bond interface
    sudo nmcli con add type bond con-name "$bondName" ifname "$bondName" bond.options "mode=1,miimon=100"
    # Set slave device
    nmcli con mod "$slaveDev1" slave-type bond master "$bondName" autoconnect yes
    nmcli con mod "$slaveDev2" slave-type bond master "$bondName" autoconnect yes
    # Set IP address
    if [ -z "$gateWay" ]    # no gateWay
    then
      sudo nmcli con mod "$bondName" ipv4.addresses "$ipAddress" ipv4.method manual autoconnect yes ipv6.method disabled
    else
      sudo nmcli con mod "$bondName" ipv4.addresses "$ipAddress" ipv4.gateway "$gateWay" ipv4.method manual autoconnect yes ipv6.method disabled
    fi
    # Start bonding interface
    sudo nmcli con up "$bondName"
  else
    if [ -z "$gateWay" ]    # no gateWay
    then
      sudo nmcli con mod "$devName" ipv4.addresses "$ipAddress" ipv4.method manual autoconnect yes ipv6.method disabled
    else
      sudo nmcli con mod "$devName" ipv4.addresses "$ipAddress" ipv4.gateway "$gateWay" ipv4.method manual autoconnect yes ipv6.method disabled
    fi
    sudo nmcli con up "$devName"
  fi

### RHEL 7, CentOS 7
elif [ "$OS_MAJOR" == 7 ]
then
  echo "CentOS 7 is coming soon."
  exit 1

else
  echo "What is this?"
fi
