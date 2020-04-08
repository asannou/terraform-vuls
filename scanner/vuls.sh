#!/bin/sh

set -eu

METADATA_URL=http://169.254.169.254/latest/meta-data

export AWS_DEFAULT_REGION=$(curl -s $METADATA_URL/placement/availability-zone | sed 's/.$//')

STS_ENDPOINT=https://sts.$AWS_DEFAULT_REGION.amazonaws.com
ACCOUNT_ID=$(aws --endpoint $STS_ENDPOINT sts get-caller-identity --output text --query Account)
TARGET_ACCOUNT_ID=$1
shift

ROLE_ARN=arn:aws:iam::$TARGET_ACCOUNT_ID:role/VulsRole-$ACCOUNT_ID
ROLE_SESSION_NAME=$(curl -s $METADATA_URL/instance-id)
BUCKET_NAME=vuls-ssm-$ACCOUNT_ID-$TARGET_ACCOUNT_ID

KNOWN_HOSTS_TEMP=$(mktemp)

DOCKER_SOCKET=/var/run/docker.sock
SOCKGUARD_FILENAME=sockguard.sock
SOCKGUARD_SOCKET=$PWD/$SOCKGUARD_FILENAME

DOCKER_BASE_IMAGE=vuls/vuls:0.9.1
DOCKER_IMAGE=vuls-docker
DOCKER_CVE_IMAGE=vuls/go-cve-dictionary
DOCKER_OVAL_IMAGE=vuls/goval-dictionary
DOCKER_AWS_BASE_IMAGE=amazon/aws-cli
DOCKER_AWS_IMAGE=aws-cli-session-manager
DOCKER_SOCKGUARD_IMAGE=buildkite/sockguard

assume_role() {
  set -- $(aws --endpoint $STS_ENDPOINT \
    sts assume-role \
    --role-arn $ROLE_ARN \
    --role-session-name $ROLE_SESSION_NAME \
    --output text \
    --query Credentials.[AccessKeyId,SecretAccessKey,SessionToken])
  export AWS_ACCESS_KEY_ID=$1 AWS_SECRET_ACCESS_KEY=$2 AWS_SESSION_TOKEN=$3
}

build_images() {
  docker build -t $DOCKER_IMAGE - <<__EOD__
FROM $DOCKER_BASE_IMAGE
RUN apk --no-cache add docker
__EOD__
  docker build -t $DOCKER_AWS_IMAGE - <<__EOD__
FROM $DOCKER_AWS_BASE_IMAGE
RUN curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm" -o "session-manager-plugin.rpm" \
  && yum install -y session-manager-plugin.rpm \
  && rm session-manager-plugin.rpm
__EOD__
}

run_sockguard() {
  SOCKGUARD_ID=$(docker \
    run -d \
    -v $DOCKER_SOCKET:$DOCKER_SOCKET \
    -v $PWD:/pwd \
    $DOCKER_SOCKGUARD_IMAGE \
      --filename /pwd/$SOCKGUARD_FILENAME \
      --allow-bind $PWD)
  until docker -H unix://$SOCKGUARD_SOCKET info > /dev/null 2>&1
  do
    sleep 1
  done
}

remove_sockguard() {
  docker rm -f $SOCKGUARD_ID
  rm $SOCKGUARD_SOCKET
}

describe_instances() {
  aws --output text \
    ec2 describe-instances \
    --filters 'Name=instance-state-name,Values=running' 'Name=tag:Vuls,Values=1' \
    --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`].Value|[0]]'
}

describe_instance_online() {
  aws --output text \
    ssm describe-instance-information \
    --filters "Key=InstanceIds,Values=$1" \
    --query 'InstanceInformationList[?PingStatus==`Online`].AgentVersion'
}

check_ssm_agent() {
  IFS=.
  set -- $1
  IFS=$' \t\n'
  test "$1" -ge 2 && test "$2" -ge 3 && test "$3" -ge 900
}

create_vuls_user() {
  publickey="$1"
  shift
  aws --output text \
    ssm send-command \
    --document-name CreateVulsUser \
    --parameters publickey="$publickey" \
    --instance-ids $@ \
    --output-s3-bucket-name $BUCKET_NAME \
    --query 'Command.CommandId' || true
}

update_ssm_agent() {
  aws --output text \
    ssm send-command \
    --document-name AWS-UpdateSSMAgent \
    --instance-ids $@ \
    --query 'Command.CommandId' || true
}

list_command() {
  aws --output text \
    ssm list-commands \
    --command-id $1 \
    --query 'Commands[0].Status'
}

get_object() {
  aws \
    s3 cp \
    s3://$BUCKET_NAME/$1/$2/awsrunShellScript/runShellScript/stdout -
}

check_docker() {
  ssh -n \
    -o ConnectionAttempts=3 \
    -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=yes \
    -o UserKnownHostsFile=ssh/known_hosts \
    -i ssh/id_rsa \
    vuls@$1 \
    'stty cols 1000; type docker' > /dev/null 2>&1
}

get_ids_to_update() {
  cat $KNOWN_HOSTS_TEMP | while read id name version
  do
    check_ssm_agent $version || echo $id
  done
}

get_known_hosts_ids() {
  cat $KNOWN_HOSTS_TEMP | while read id name
  do
    echo $id
  done
}

update_ssm_agents() {
  ids=$(get_ids_to_update | paste -s)
  test -z "$ids" && return
  update_ssm_agent $ids
}

send_public_key() {
  public_key="$(cat ssh/id_rsa.pub)"
  ids=$(get_known_hosts_ids | paste -s)
  create_vuls_user "$public_key" $ids
}

wait_command() {
  test -z "$1" && return
  for i in $(seq 10)
  do
    status=$(list_command $1)
    case "$status" in
      'Success') return ;;
      'Failed') return 1 ;;
    esac
    sleep 5
  done
  return 1
}

make_server_config() {
  cat <<__EOD__
[servers."$1"]
host = "$2"
__EOD__
}

make_containers_config() {
  cat <<__EOD__
[servers."$1".containers]
includes = ["\${running}"]
__EOD__
}

make_server_configs() {
  describe_instances | while read INSTANCE
  do
    IFS=$'\t'
    set -- $INSTANCE
    INSTANCE_ID=$1
    NAME=$2
    AGENT_VERSION=$(describe_instance_online $INSTANCE_ID)
    test -z "$AGENT_VERSION" && continue
    echo "$INSTANCE_ID $NAME $AGENT_VERSION" >> $KNOWN_HOSTS_TEMP
    make_server_config $NAME $INSTANCE_ID >> config.toml
  done
}

make_containers_configs() {
  cat $KNOWN_HOSTS_TEMP | while read id name
  do
    if check_docker $id
    then
      make_containers_config $name
    fi
  done >> config.toml
}

make_ssh_config() {
  cat <<__EOD__
host i-*
ProxyCommand sh -c "docker run -i --rm -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN $DOCKER_AWS_IMAGE ssm start-session --target %h --document-name AWS-StartSSHSession --parameters 'portNumber=%p'"
__EOD__
}

make_known_hosts() {
  command_id=$1
  cat $KNOWN_HOSTS_TEMP | while read id name
  do
    hostkey=$(get_object $command_id $id)
    echo "$id $hostkey"
  done > ssh/known_hosts
}

setup() {
  make_server_configs

  wait_command "$(update_ssm_agents)"

  command_id=$(send_public_key)
  wait_command $command_id

  make_known_hosts $command_id
  make_containers_configs
}

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

run_vuls() {
  docker -H unix://$SOCKGUARD_SOCKET \
    run --rm \
    -v $SOCKGUARD_SOCKET:$DOCKER_SOCKET \
    -v $PWD/ssh:/root/.ssh:ro \
    -v $PWD:/vuls \
    -v $PWD/log:/var/log/vuls \
    -e AWS_ACCESS_KEY_ID \
    -e AWS_SECRET_ACCESS_KEY \
    -e AWS_SESSION_TOKEN \
    $DOCKER_IMAGE \
    "$@"
}

if [ ! -d ssh ]
then
  mkdir -m 700 ssh
  ssh-keygen -N '' -f ssh/id_rsa
fi

cp $(dirname $0)/config.toml.default config.toml

assume_role

setup

run_cve fetchnvd -last2y
run_cve fetchjvn -last2y

fetch_oval fetch-debian 7 8 9 10
fetch_oval fetch-redhat 5 6 7 8
fetch_oval fetch-ubuntu 14 16 18 19 20
fetch_oval fetch-alpine 3.3 3.4 3.5 3.6 3.7 3.8 3.9 3.10 3.11
fetch_oval fetch-amazon

build_images
trap remove_sockguard EXIT
run_sockguard
make_ssh_config > ssh/config

run_vuls scan && run_vuls report "$@" || true

