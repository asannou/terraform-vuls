#!/bin/sh

set -eu

METADATA_URL=http://169.254.169.254/latest/meta-data

AWS_DEFAULT_REGION=$(curl -s $METADATA_URL/placement/availability-zone | sed 's/.$//')
export AWS_DEFAULT_REGION

STS_ENDPOINT=https://sts.$AWS_DEFAULT_REGION.amazonaws.com
ACCOUNT_ID=$(aws --endpoint $STS_ENDPOINT sts get-caller-identity --output text --query Account)
TARGET_ACCOUNT_ID=$1
shift

MACS_URL=$METADATA_URL/network/interfaces/macs
MAC=$(curl -s $MACS_URL/ | head -n 1)
VPC_ID=$(curl -s $MACS_URL/${MAC}vpc-id)
ROLE_ARN=arn:aws:iam::$TARGET_ACCOUNT_ID:role/VulsRole-$ACCOUNT_ID
ROLE_SESSION_NAME=$(curl -s $METADATA_URL/instance-id)
BUCKET_NAME=vuls-ssm-$ACCOUNT_ID-$TARGET_ACCOUNT_ID

KNOWN_HOSTS_TEMP=$(mktemp)
DOCKER_IMAGE=vuls/vuls@sha256:6cfecadb1d5b17c32375a1a2e814e15955c140c67e338024db0c6e81c3560c80
DOCKER_CVE_IMAGE=vuls/go-cve-dictionary

assume_role() {
  set -- $(aws --endpoint $STS_ENDPOINT \
    sts assume-role \
    --role-arn $ROLE_ARN \
    --role-session-name $ROLE_SESSION_NAME \
    --output text \
    --query Credentials.[AccessKeyId,SecretAccessKey,SessionToken])
  ACCESS_KEY_ID=$1
  SECRET_ACCESS_KEY=$2
  SESSION_TOKEN=$3
}

assumed_aws() {
  AWS_ACCESS_KEY_ID=$ACCESS_KEY_ID \
  AWS_SECRET_ACCESS_KEY=$SECRET_ACCESS_KEY \
  AWS_SESSION_TOKEN=$SESSION_TOKEN \
    aws "$@"
}

describe_security_group() {
  aws --output text \
    ec2 describe-security-groups \
    --filters 'Name=group-name,Values=vuls-vpce' "Name=vpc-id,Values=$VPC_ID" \
    --query 'SecurityGroups[0].GroupId'
}

describe_vpce_svc() {
  assumed_aws --output text \
    ec2 describe-vpc-endpoint-service-configurations \
    --filters 'Name=tag:Name,Values=vuls' \
    --query 'ServiceConfigurations[].[ServiceId,ServiceName,NetworkLoadBalancerArns[0],AvailabilityZones[0]]'
}

describe_az() {
  assumed_aws --output text \
    ec2 describe-availability-zones \
    --zone-names $1 \
    --query 'AvailabilityZones[0].ZoneId'
}

describe_subnet() {
  aws --output text \
    ec2 describe-subnets \
    --filters "Name=tag:Name,Values=vuls-vpce-$1" "Name=availability-zone-id,Values=$1" \
    --query 'Subnets[0].SubnetId'
}

create_tag() {
  aws --output text \
    ec2 create-tags \
    --resources $@ \
    --tags 'Key=Name,Value=vuls'
}

create_vpce() {
  security_group=$(describe_security_group)
  aws --output text \
    ec2 create-vpc-endpoint \
    --vpc-endpoint-type Interface \
    --service-name $1 \
    --vpc-id $VPC_ID \
    --subnet-ids $2 \
    --security-group-ids $security_group \
    --query 'VpcEndpoint.[VpcEndpointId,DnsEntries[0].DnsName]'
}

get_rest_api_id() {
  assumed_aws --output text \
    apigateway get-rest-apis \
    --query 'items[?name==`vuls`].id'
}

accept_vpce() {
  outfile=$(mktemp)
  api_id=$(get_rest_api_id)
  invoke_url="https://$api_id.execute-api.$AWS_DEFAULT_REGION.amazonaws.com/prod/accept-vpc-endpoint-connections"
  ./awscurl-lite \
    -X POST \
    -d '{"serviceId": "'$1'", "vpcEndpointIds": ["'$2'"]}' \
    $invoke_url > $outfile
  jp.py -f $outfile 'Unsuccessful[]'
  rm $outfile
}

describe_vpce_state() {
  aws --output text \
    ec2 describe-vpc-endpoints \
    --vpc-endpoint-ids $1 \
    --query 'VpcEndpoints[0].State'
}

wait_vpces() {
  for vpce_id in $@
  do
    for i in $(seq 10)
    do
      state=$(describe_vpce_state $vpce_id)
      test "$state" = 'available' && continue 2
      sleep 30
    done
    return 1
  done
}

delete_vpces() {
  aws --output text \
    ec2 delete-vpc-endpoints \
    --vpc-endpoint-ids $@ \
    --query 'Unsuccessful[]'
}

describe_listeners() {
  assumed_aws --output text \
    elbv2 describe-listeners \
    --load-balancer-arn $1 \
    --query 'Listeners[].[Port,DefaultActions[0].TargetGroupArn]'
}

describe_target() {
  assumed_aws --output text \
    elbv2 describe-target-health \
    --target-group-arn $1 \
    --query 'TargetHealthDescriptions[0].[Target.Id,TargetHealth.State]'
}

describe_tag() {
  assumed_aws --output text \
    ec2 describe-tags \
    --filters "Name=resource-id,Values=$1" "Name=key,Values=$2" \
    --query 'Tags[0].Value'
}

describe_instance_online() {
  assumed_aws --output text \
    ssm describe-instance-information \
    --filters "Key=InstanceIds,Values=$1" \
    --query 'InstanceInformationList[?PingStatus==`Online`].InstanceId'
}

send_command() {
  publickey="$1"
  shift
  assumed_aws --output text \
    ssm send-command \
    --document-name CreateVulsUser \
    --parameters publickey="$publickey" \
    --instance-ids $@ \
    --output-s3-bucket-name $BUCKET_NAME \
    --query 'Command.CommandId' || true
}

list_command() {
  assumed_aws --output text \
    ssm list-commands \
    --command-id $1 \
    --query 'Commands[0].Status'
}

get_object() {
  assumed_aws \
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
    -p $2 \
    vuls@$1 \
    'stty cols 1000; type docker' > /dev/null 2>&1
}

create_vpces() {
  describe_vpce_svc | while read vpce_svc_id vpce_svc_name vpce_svc_lb vpce_svc_az
  do
    vpce_svc_az_id=$(describe_az $vpce_svc_az)
    vpce_svc_subnet_id=$(describe_subnet $vpce_svc_az_id)
    create_vpce $vpce_svc_name $vpce_svc_subnet_id | while read vpce_id vpce_name
    do
      create_tag $vpce_id
      unsuccessful=$(accept_vpce $vpce_svc_id $vpce_id)
      test "$unsuccessful" != '[]' && continue 2
      echo "$vpce_id $vpce_name $vpce_svc_lb"
    done
  done
}

get_known_hosts_ids() {
  cat $KNOWN_HOSTS_TEMP | while read hostname port id name
  do
    echo $id
  done
}

send_public_key() {
  public_key="$(cat ssh/id_rsa.pub)"
  send_command "$public_key" $(get_known_hosts_ids | paste -s)
}

wait_command() {
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
port = "$3"
__EOD__
}

make_containers_config() {
  cat <<__EOD__
[servers."$1".containers]
includes = ["\${running}"]
__EOD__
}

make_server_configs() {
  create_vpces | while read vpce_id vpce_name vpce_svc_lb
  do
    echo $vpce_id
    describe_listeners $vpce_svc_lb | while read port target_group
    do
      describe_target $target_group | while read id state
      do
        if [ "$state" = 'healthy' ]
        then
          if [ "$(describe_tag $id 'Vuls')" = "1" ]
          then
            test -z "$(describe_instance_online $id)" && continue
            name="$(describe_tag $id 'Name')"
            test -z "$name" && name=$id
            echo "$vpce_name $port $id $name" >> $KNOWN_HOSTS_TEMP
            make_server_config $name $vpce_name $port >> config.toml
          fi
        fi
      done
    done
  done
}

make_containers_configs() {
  cat $KNOWN_HOSTS_TEMP | while read hostname port id name
  do
    if check_docker $hostname $port
    then
      make_containers_config $name
    fi
  done >> config.toml
}

make_known_hosts() {
  command_id=$1
  cat $KNOWN_HOSTS_TEMP | while read hostname port id
  do
    hostkey=$(get_object $command_id $id)
    echo "[$hostname]:$port $hostkey"
  done > ssh/known_hosts
}

setup() {
  vpce_ids=$(make_server_configs | paste -s)
  trap "delete_vpces $vpce_ids; rm $KNOWN_HOSTS_TEMP" EXIT

  command_id=$(send_public_key)
  test -n "$command_id"

  wait_vpces $vpce_ids
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

run_vuls() {
  docker run --rm -i \
    -v $PWD/ssh:/root/.ssh:ro \
    -v $PWD:/vuls \
    -v $PWD/log:/var/log/vuls \
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
run_vuls scan && run_vuls report "$@" || true

