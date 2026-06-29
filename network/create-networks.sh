#!/usr/bin/env sh
set -eu

create_network() {
  network_name="$1"
  if docker network inspect "$network_name" >/dev/null 2>&1; then
    echo "Network $network_name đã tồn tại"
  else
    docker network create "$network_name"
  fi
}

create_network opp-database-network
create_network opp-auth-network
