#!/bin/sh

set -eu

METADATA_URL=http://169.254.169.254/latest/meta-data

export AWS_DEFAULT_REGION=$(curl -s $METADATA_URL/placement/availability-zone | sed 's/.$//')

STS_ENDPOINT=https://sts.$AWS_DEFAULT_REGION.amazonaws.com
ACCOUNT_ID=$(aws --endpoint $STS_ENDPOINT sts get-caller-identity --output text --query Account)
TARGET_ACCOUNT_ID=$1 && shift
TARGET_INSTANCE_TAG_NAME=Vuls
TARGET_INSTANCE_TAG_VALUE=1

ROLE_ARN=arn:aws:iam::$TARGET_ACCOUNT_ID:role/VulsRole-$ACCOUNT_ID
ROLE_SESSION_NAME=$(curl -s $METADATA_URL/instance-id)
BUCKET_NAME=vuls-ssm-$ACCOUNT_ID-$TARGET_ACCOUNT_ID

DOCKER_SOCKET=/var/run/docker.sock
SOCKGUARD_FILENAME=sockguard.sock
SOCKGUARD_SOCKET=$PWD/$SOCKGUARD_FILENAME

DOCKER_BASE_IMAGE=vuls/vuls:0.9.3
DOCKER_IMAGE=vuls-docker
DOCKER_AWS_BASE_IMAGE=amazon/aws-cli
DOCKER_AWS_IMAGE=aws-cli-session-manager
DOCKER_SOCKGUARD_IMAGE=buildkite/sockguard

SLACK_WEBHOOK_URL_SECRET_ID=vuls-slack-webhook-url

generate_ssh_key() {
  test -d ssh && return
  mkdir -m 700 ssh
  ssh-keygen -N '' -f ssh/id_rsa
}

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
  docker pull $DOCKER_BASE_IMAGE
  docker build -t $DOCKER_IMAGE - <<__EOD__
FROM $DOCKER_BASE_IMAGE
RUN apk --no-cache add docker
__EOD__
  docker pull $DOCKER_AWS_BASE_IMAGE
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
    --filters 'Name=instance-state-name,Values=running' "Name=tag:$TARGET_INSTANCE_TAG_NAME,Values=$TARGET_INSTANCE_TAG_VALUE" \
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
  publickey="$1" && shift
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

get_secret_value() {
  aws --output text \
    secretsmanager get-secret-value \
    --secret-id $1 \
    --query SecretString
}

check_docker() {
  ssh -n \
    -o ConnectionAttempts=3 \
    -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=yes \
    -o UserKnownHostsFile=ssh/known_hosts \
    -F ssh/config \
    -i ssh/id_rsa \
    vuls@$1 \
    'stty cols 1000; docker ps' > /dev/null 2>&1
}

get_ids_to_update() {
  while read id name version
  do
    check_ssm_agent $version || echo $id
  done
}

get_known_hosts_ids() {
  while read id name version
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

make_default_config() {
  cat <<__EOD__
[default]
port = "22"
user = "vuls"
keyPath = "/root/.ssh/id_rsa"
scanMode = ["fast-root"]

__EOD__
}

make_slack_config() {
  cat config.slack.toml
  cat <<__EOD__
hookURL = "$(get_secret_value $SLACK_WEBHOOK_URL_SECRET_ID)"

__EOD__
}

make_server_config() {
  cat <<__EOD__
[servers."$1"]
host = "$2"
__EOD__
}

make_containers_config() {
  cat <<__EOD__
containerType = "docker"
containersIncluded = ["\${running}"]
__EOD__
}

make_instance_list() {
  describe_instances | while read instance
  do
    IFS=$'\t'
    set -- $instance
    instance_id=$1
    name=$2
    agent_version=$(describe_instance_online $instance_id)
    test -z "$agent_version" && continue
    echo "$instance_id $name $agent_version"
  done
}

make_server_configs() {
  echo '[servers]'
  while read id name version
  do
    make_server_config $name $id
    if check_docker $id
    then
      make_containers_config
    fi
  done
}

make_ssh_config() {
  cat <<__EOD__
host i-*
ProxyCommand sh -c "docker run -i --rm -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN $DOCKER_AWS_IMAGE ssm start-session --target %h --document-name AWS-StartSSHSession --parameters 'portNumber=%p'"
__EOD__
}

make_known_hosts() {
  command_id=$1
  while read id name version
  do
    hostkey=$(get_object $command_id $id)
    echo "$id $hostkey"
  done
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

generate_ssh_key

make_default_config > config.toml
make_slack_config >> config.toml

assume_role

temp_instance_list=$(mktemp)
make_instance_list >> $temp_instance_list

wait_command "$(update_ssm_agents < $temp_instance_list)"

command_id=$(send_public_key < $temp_instance_list)
wait_command $command_id

make_known_hosts $command_id < $temp_instance_list > ssh/known_hosts
make_server_configs < $temp_instance_list >> config.toml

rm $temp_instance_list

build_images
trap remove_sockguard EXIT
run_sockguard
make_ssh_config > ssh/config

run_vuls scan && run_vuls report "$@" || true

