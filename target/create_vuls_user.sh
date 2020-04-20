#!/bin/sh

USER=vuls
DOTSSH=/home/$USER/.ssh
COMMAND=$DOTSSH/vuls-ssh-command.sh

useradd -m $USER 2> /dev/null
mkdir -m 700 $DOTSSH
aws s3 cp {{sshcommand}} $COMMAND > /dev/null
echo "command=\"$COMMAND\" {{publickey}}" > $DOTSSH/authorized_keys
chmod 700 $COMMAND
chown -R $USER:$USER $DOTSSH

cat /etc/ssh/ssh_host_ecdsa_key.pub

exec > /dev/null

# https://vuls.io/docs/en/usage-configtest.html#etc-sudoers

test -e /etc/debian_version && cat > /etc/sudoers.d/vuls <<__EOD__
$USER ALL=(ALL) NOPASSWD: /usr/bin/apt-get update, /usr/bin/stat *, /usr/sbin/checkrestart, /bin/ls -l /proc/*/exe, /bin/cat /proc/*/maps, /usr/bin/lsof -i -P -n
Defaults:$USER env_keep="http_proxy https_proxy HTTP_PROXY HTTPS_PROXY"
__EOD__

test -e /etc/centos-release || grep 'Amazon Linux' /etc/system-release > /dev/null 2>&1 && cat > /etc/sudoers.d/vuls <<__EOD__
$USER ALL=(ALL) NOPASSWD: /usr/bin/stat, /usr/bin/needs-restarting, /usr/bin/which, /bin/ls -l /proc/*/exe, /bin/cat /proc/*/maps, /usr/sbin/lsof -i -P -n
Defaults:$USER env_keep="http_proxy https_proxy HTTP_PROXY HTTPS_PROXY"
__EOD__

test -e /etc/redhat-release && cat > /etc/sudoers.d/vuls <<__EOD__
$USER ALL=(ALL) NOPASSWD: /usr/bin/stat, /usr/bin/needs-restarting, /usr/bin/which, /usr/bin/repoquery, /usr/bin/yum makecache, /bin/ls -l /proc/*/exe, /bin/cat /proc/*/maps, /usr/bin/lsof -i -P -n, /usr/sbin/lsof -i -P -n
Defaults:$USER env_keep="http_proxy https_proxy HTTP_PROXY HTTPS_PROXY"
__EOD__

test -e /etc/oracle-release && cat > /etc/sudoers.d/vuls <<__EOD__
$USER ALL=(ALL) NOPASSWD: /usr/bin/stat, /usr/bin/needs-restarting, /usr/bin/which, /usr/bin/repoquery, /usr/bin/yum makecache
Defaults:$USER env_keep="http_proxy https_proxy HTTP_PROXY HTTPS_PROXY"
__EOD__

if type docker
then
  groupadd docker
  usermod -aG docker $USER
fi
