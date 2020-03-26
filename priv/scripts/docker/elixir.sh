#!/bin/bash

set -euox pipefail

elixir=$1
erlang=$2
os=$3
os_version=$4
arch=$5

tag=${elixir}-erlang-${erlang}-${os}-${os_version}
erlang_major=$(echo "${erlang}" | awk 'match($0, /^[0-9][0-9]/) { print substr( $0, RSTART, RLENGTH )}')

docker build -t hexpm/elixir-${arch}:${tag} --build-arg ELIXIR=${elixir} --build-arg ERLANG=${erlang} --build-arg ERLANG_MAJOR=${erlang_major} --build-arg OS_VERSION=${os_version} --build-arg ARCH=${arch} -f ${SCRIPT_DIR}/docker/elixir-${os}.dockerfile ${SCRIPT_DIR}/docker
docker push docker.io/hexpm/elixir-${arch}:${tag}
docker rmi -f docker.io/hexpm/elixir-${arch}:${tag}
