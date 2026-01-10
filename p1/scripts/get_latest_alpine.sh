#!/bin/bash

# Fetch latest Alpine versions from releases page
ALPINE_VERSIONS=$(curl -s "https://alpinelinux.org/releases/" | grep -oP 'v3\.\d+' | tr -d 'v.' | sort -rn -u | head -10)

# Try each version from latest to oldest
for ver in $ALPINE_VERSIONS; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 3 "https://app.vagrantup.com/api/v2/vagrant/generic/alpine${ver}")
    if [ "$HTTP_CODE" = "200" ]; then
        echo "generic/alpine${ver}"
        exit 0
    fi
done
