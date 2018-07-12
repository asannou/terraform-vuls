#!/bin/sh

#echo "$SSH_ORIGINAL_COMMAND" >> /tmp/vuls-ssh-command.debug

# stty cols 1000; ls /etc/debian_version
# stty cols 1000; ls /etc/fedora-release
# stty cols 1000; ls /etc/oracle-release
# stty cols 1000; ls /etc/centos-release
# stty cols 1000; ls /etc/redhat-release
# stty cols 1000; ls /etc/system-release
# stty cols 1000; cat /etc/system-release
# stty cols 1000; type curl
# stty cols 1000; curl --max-time 1 --retry 3 --noproxy 169.254.169.254 http://169.254.169.254/latest/meta-data/instance-id
# stty cols 1000; /sbin/ip -o addr
# stty cols 1000; uname -r
# stty cols 1000; rpm -qa --queryformat "%{NAME} %{EPOCH} %{VERSION} %{RELEASE} %{ARCH}
# "
# stty cols 1000; rpm -q --last kernel
# stty cols 1000; repoquery --all --pkgnarrow=updates --qf="%{NAME} %{EPOCH} %{VERSION} %{RELEASE} %{REPO}"
# stty cols 1000; yum --color=never --security updateinfo list updates
# stty cols 1000; yum --color=never --security updateinfo updates

# stty cols 1000; docker ps --format '{{.ID}} {{.Names}} {{.Image}}'
# stty cols 1000; docker ps --filter 'status=exited' --format '{{.ID}} {{.Names}} {{.Image}}'
# stty cols 1000; docker exec --user 0 deadbeefdead /bin/sh -c 'ls /etc/debian_version'
# stty cols 1000; docker exec --user 0 deadbeefdead /bin/sh -c 'cat /etc/issue'
# stty cols 1000; docker exec --user 0 deadbeefdead /bin/sh -c 'lsb_release -ir'
# stty cols 1000; docker exec --user 0 deadbeefdead /bin/sh -c 'cat /etc/lsb-release'
# stty cols 1000; docker exec --user 0 deadbeefdead /bin/sh -c 'cat /etc/debian_version'
# stty cols 1000; docker exec --user 0 deadbeefdead /bin/sh -c 'type curl'
# stty cols 1000; docker exec --user 0 deadbeefdead /bin/sh -c 'type wget'
# stty cols 1000; docker exec --user 0 deadbeefdead /bin/sh -c '/sbin/ip -o addr'
# stty cols 1000; docker exec --user 0 deadbeefdead /bin/sh -c 'uname -r'
# stty cols 1000; docker exec --user 0 deadbeefdead /bin/sh -c 'uname -a'
# stty cols 1000; docker exec --user 0 deadbeefdead /bin/sh -c 'test -f /var/run/reboot-required'
# stty cols 1000; docker exec --user 0 deadbeefdead /bin/sh -c 'dpkg-query -W -f="\${binary:Package},\${db:Status-Abbrev},\${Version},\${Source},\${source:Version}\n"'
# stty cols 1000; docker exec --user 0 deadbeefdead /bin/sh -c 'apt-get update'
# stty cols 1000; docker exec --user 0 deadbeefdead /bin/sh -c 'LANGUAGE=en_US.UTF-8 apt-get dist-upgrade --dry-run'
# stty cols 1000; docker exec --user 0 deadbeefdead /bin/sh -c 'LANGUAGE=en_US.UTF-8 apt-cache policy '

test_stty() {
  IFS=' '
  set -- $1
  test "$1" = "stty" -a "$2" = "cols"
}

escape() {
  tr '\n' '\0' | sed 's/\x0/\\n/g;s/\t/\\t/g'
}

exec_command() {
  IFS=$'\t'
  set -- $(echo "$@" | xargs printf '%s\t')
  exec "$@"
}

verify_enviroment() {
  case "$1" in
    LANGUAGE=*)
      echo "$1"
      ;;
  esac
}

verify_command() {
  case "$1" in
    ls|type|lsb_release|uname|test|repoquery|dpkg-query|apt-cache)
      echo "$@"
      ;;
    cat)
      case "$2" in
        /etc/system-release|/etc/issue|/etc/lsb-release|/etc/debian_version)
          echo "$@"
          ;;
      esac
      ;;
    curl)
      echo curl --max-time 1 --retry 3 --noproxy 169.254.169.254 http://169.254.169.254/latest/meta-data/instance-id
      ;;
    /sbin/ip)
      echo /sbin/ip -o addr
      ;;
    yum)
      [ "$4" = "updateinfo" ] && echo "$@"
      ;;
    rpm)
      case "$2" in
        -qa)
          echo "$@"
          ;;
        *)
          echo rpm -q --last kernel
          ;;
      esac
      ;;
    apt-get)
      case "$2" in
        update)
          echo apt-get update
          ;;
        dist-upgrade)
          echo apt-get dist-upgrade --dry-run
          ;;
      esac
      ;;
    docker)
      case "$2" in
        ps)
          echo "$@"
          ;;
        exec)
          options="--user 0"
          container_id="$5"
          IFS=$'\t'
          set -- $(echo "$@" | xargs printf '%s\t')
          IFS=' '
          set -- $8
          enviroment=$(verify_enviroment "$@")
          if [ -n "$enviroment" ]
          then
            options="$options --env '$enviroment'"
            shift
          fi
          command=$(verify_command "$@")
          [ -n "$command" ] && echo docker exec $options $container_id $command
          ;;
      esac
      ;;
  esac
}

IFS=';'
set -- $SSH_ORIGINAL_COMMAND

if test_stty "$1"
then
  $1
else
  exit 126
fi

IFS=' '
set -- $(printf '%s' "$2" | escape)

enviroment=$(verify_enviroment "$@")
if [ -n "$enviroment" ]
then
  export "$enviroment"
  shift
fi

set -- $(verify_command "$@")

case "$1" in
  "")
    exit 126
    ;;
  type)
    "$@"
    exit $?
    ;;
  *)
    exec_command "$@"
    ;;
esac
