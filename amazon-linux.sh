#!/bin/sh

# stty cols 1000; ls /etc/debian_version
# stty cols 1000; ls /etc/fedora-release
# stty cols 1000; ls /etc/oracle-release
# stty cols 1000; ls /etc/redhat-release
# stty cols 1000; ls /etc/system-release
# stty cols 1000; cat /etc/system-release
# stty cols 1000; type curl
# stty cols 1000; curl --max-time 1 --retry 3 --noproxy 169.254.169.254 http://169.254.169.254/latest/meta-data/instance-id
# stty cols 1000; rpm -qa --queryformat '%{NAME}	%{VERSION}	%{RELEASE}
# '
# stty cols 1000; yum --color=never repolist
# stty cols 1000; yum --color=never --security updateinfo list updates
# stty cols 1000; LANGUAGE=en_US.UTF-8 yum --color=never check-update
# stty cols 1000; yum --color=never --security updateinfo updates

escape() {
  tr '\n' '\0' | sed 's/\x0/\\n/g;s/\t/\\t/g'
}

get_instance_id() {
  stty cols 1000
  exec curl --max-time 1 --retry 3 --noproxy 169.254.169.254 http://169.254.169.254/latest/meta-data/instance-id
}

exec_command() {
  stty cols 1000
  IFS=$'\t'
  set -- $(echo "$@" | xargs -n 1 printf '%s\t')
  exec "$@"
}

IFS=';'
set -- $SSH_ORIGINAL_COMMAND
IFS=' '
set -- $(printf '%s' "$2" | escape)

case "$1" in
  LANGUAGE=*)
    shift
    LANGUAGE=en_US.UTF-8
    ;;
esac

case "$1" in
  curl)
    get_instance_id
    ;;
  ls|cat|type|rpm|yum)
    exec_command "$@"
    ;;
esac

exit 1

