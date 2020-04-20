#!/bin/sh

USER=vuls
DOTSSH=/home/$USER/.ssh
COMMAND=$DOTSSH/vuls-ssh-command.sh

useradd -m $USER
mkdir -m 700 $DOTSSH
aws s3 cp {{sshcommand}} $COMMAND > /dev/null
echo "command=\"$COMMAND\" {{publickey}}" > $DOTSSH/authorized_keys
chmod 700 $COMMAND
chown -R $USER:$USER $DOTSSH

cat /etc/ssh/ssh_host_ecdsa_key.pub

exec > /dev/null

if [ -e /etc/redhat-release ]
then
  printf '%s\n' $USER' ALL=(ALL) NOPASSWD:/usr/bin/yum --color=never repolist, /usr/bin/yum --color=never --security updateinfo list updates, /usr/bin/yum --color=never --security updateinfo updates, /usr/bin/repoquery, /usr/bin/yum --color=never changelog all *' 'Defaults:'$USER' env_keep="http_proxy https_proxy HTTP_PROXY HTTPS_PROXY"' > /etc/sudoers.d/vuls
fi

if [ -e /etc/debian_version ]
then
  printf '%s\n' $USER' ALL=(ALL) NOPASSWD: /usr/bin/apt-get update' 'Defaults:'$USER' env_keep="http_proxy https_proxy HTTP_PROXY HTTPS_PROXY"' > /etc/sudoers.d/vuls
fi

if type docker
then
  groupadd docker
  usermod -aG docker $USER
fi
