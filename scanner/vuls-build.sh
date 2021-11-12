#!/bin/sh

set -eu

CVE_VERSION=0.6.2
OVAL_VERSION=0.3.5
GOST_VERSION=0.1.10
VULS_VERSION=0.9.3
SOCKGUARD_VERSION=1.0.0

GIT_CVE_URL=https://github.com/vulsio/go-cve-dictionary
GIT_OVAL_URL=https://github.com/vulsio/goval-dictionary
GIT_GOST_URL=https://github.com/vulsio/gost
GIT_VULS_URL=https://github.com/future-architect/vuls
GIT_SOCKGUARD_URL=https://github.com/buildkite/sockguard

DOCKER_CVE_IMAGE=vuls/go-cve-dictionary:$CVE_VERSION
DOCKER_OVAL_IMAGE=vuls/goval-dictionary:$OVAL_VERSION
DOCKER_GOST_IMAGE=asannou/gost:$GOST_VERSION
DOCKER_VULS_IMAGE=vuls/vuls:$VULS_VERSION
DOCKER_SOCKGUARD_IMAGE=buildkite/sockguard

git_clone() {
  git clone --depth 1 --branch $2 $1 $3 > /dev/null 2>&1
}

while read url version docker_image
do
  temp=$(mktemp -d)
  git_clone $url v$version $temp
  patch=$(dirname $0)/$(basename $url).patch
  test -r $patch && git -C $temp apply < $patch
  docker build $temp --tag $docker_image
  rm -fr $temp
done << __EOD__
$GIT_CVE_URL $CVE_VERSION $DOCKER_CVE_IMAGE
$GIT_OVAL_URL $OVAL_VERSION $DOCKER_OVAL_IMAGE
$GIT_GOST_URL $GOST_VERSION $DOCKER_GOST_IMAGE
$GIT_VULS_URL $VULS_VERSION $DOCKER_VULS_IMAGE
$GIT_SOCKGUARD_URL $SOCKGUARD_VERSION $DOCKER_SOCKGUARD_IMAGE
__EOD__

