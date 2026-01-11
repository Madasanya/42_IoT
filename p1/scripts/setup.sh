#!/bin/bash

apk update
apk add --no-cache python3 openssh
rc-update add sshd
rc-service sshd start
