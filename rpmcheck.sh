#!/bin/bash
########################################################
# Description : Check necessary rpm for Oracle
# Create DATE : 2020.10.21
# Last Update DATE : 2020.10.21 by ashurei
# Copyright (c) Technical Solution, 2020
########################################################

# https://github.com/fearside/ProgressBar/blob/master/progressbar.sh
# 1. Create ProgressBar function
# 1.1 Input is currentState($1) and totalState($2)
function ProgressBar {
# Process data
        let _progress=(${1}*100/${2}*100)/100
        let _done=(${_progress}*4)/10
        let _left=40-$_done
# Build progressbar string lengths
        _done=$(printf "%${_done}s")
        _left=$(printf "%${_left}s")

# 1.2 Build progressbar strings and print the ProgressBar line
# 1.2.1 Output example:
# 1.2.1.1 Progress : [########################################] 100%
printf "\rProgress : [${_done// /#}${_left// /-}] ${_progress}%%"
}

FILE="$1"
### Check 'RPM LIST' file
if [[ -z ${FILE} || ! -f ${FILE} ]]
then
        printf "Prepare the rpm check txt.\n"
        printf "Usage) rpmcheck.sh <RPM LIST>"
        exit 1
fi

### Set variables
RPMFILE=$(cat ${FILE})
LINE=$(cat ${FILE} | wc -l)

### Loop 'rpm -qa'
i=0
for rf in $RPMFILE
do
        IS_RPM=$(rpm -qa | grep ^${rf}-[0-9] | wc -l)
        if [ ${IS_RPM} -eq 0 ]
        then
                printf "\n\"${rf}\" is not installed.\n"
        fi
        let "i++"
        ProgressBar $i $LINE
done

printf '\nFinished!\n'
