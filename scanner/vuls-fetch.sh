#!/bin/sh

set -eu

CVE_VERSION=0.6.2
OVAL_VERSION=0.3.5
GOST_VERSION=0.1.10

DOCKER_CVE_IMAGE=vuls/go-cve-dictionary:$CVE_VERSION
DOCKER_OVAL_IMAGE=vuls/goval-dictionary:$OVAL_VERSION
DOCKER_GOST_IMAGE=asannou/gost:$GOST_VERSION

run_cve() {
  docker run --rm -i \
    -v $PWD:/vuls \
    -v $PWD/go-cve-dictionary-log:/var/log/vuls \
    $DOCKER_CVE_IMAGE \
    "$@"
}

fetch_oval() {
  docker run --rm -i \
    -v $PWD:/vuls \
    -v $PWD/goval-dictionary-log:/var/log/vuls \
    $DOCKER_OVAL_IMAGE \
    "$@"
}

fetch_gost() {
  docker run --rm -i \
    -v $PWD:/vuls \
    -v $PWD/gost-log:/var/log/gost \
    $DOCKER_GOST_IMAGE \
    fetch "$@"
}

run_cve fetchnvd -last2y
run_cve fetchjvn -last2y

fetch_oval fetch-debian 7 8 9 10 11
fetch_oval fetch-redhat 5 6 7 8
fetch_oval fetch-ubuntu 14 16 18 19 20 21
fetch_oval fetch-alpine 3.3 3.4 3.5 3.6 3.7 3.8 3.9 3.10 3.11 3.12 3.13 3.14
fetch_oval fetch-amazon

fetch_gost debian

