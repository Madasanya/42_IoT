#!/usr/bin/env bash

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <namespace> <service-name> <local-port:remote-port>"
  exit 1
fi

NAMESPACE=$1
SERVICE_NAME=$2
PORTS=$3
echo "Starting port-forwarding for service '$SERVICE_NAME' in namespace '$NAMESPACE' on ports '$PORTS'..."
while true; do
  sudo kubectl port-forward svc/"$SERVICE_NAME" -n "$NAMESPACE" "$PORTS"
  sleep 3
done