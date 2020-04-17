#!/bin/sh

set -eu

DOCKER_CVE_IMAGE=vuls/go-cve-dictionary
DOCKER_OVAL_IMAGE=vuls/goval-dictionary

run_cve() {
  docker pull $DOCKER_CVE_IMAGE
  docker run --rm -i \
    -v $PWD:/vuls \
    -v $PWD/go-cve-dictionary-log:/var/log/vuls \
    $DOCKER_CVE_IMAGE \
    "$@"
}

fetch_oval() {
  docker pull $DOCKER_OVAL_IMAGE
  docker run --rm -i -v $PWD:/vuls -v $PWD/goval-dictionary-log:/var/log/vuls $DOCKER_OVAL_IMAGE "$@"
}

run_cve fetchnvd -last2y
run_cve fetchjvn -last2y

fetch_oval fetch-debian 7 8 9 10
fetch_oval fetch-redhat 5 6 7 8
fetch_oval fetch-ubuntu 14 16 18 19 20
fetch_oval fetch-alpine 3.3 3.4 3.5 3.6 3.7 3.8 3.9 3.10 3.11
fetch_oval fetch-amazon

