#!/bin/bash
USER="suser"
HOST="60.30.136.192"
PASSWORD="skt7979"

while true
do
  sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USER@$HOST" "exit"
  sleep 2
done
