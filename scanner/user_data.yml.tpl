#cloud-config

timezone: "Asia/Tokyo"

repo_update: true
repo_upgrade: all

packages:
 - yum-cron
 - yum-utils
 - git

runcmd:
 - systemctl stop docker docker.socket ecs amazon-ecs-volume-plugin
 - systemctl disable ecs amazon-ecs-volume-plugin
 - rm /run/docker/plugins/amazon-ecs-volume-plugin.sock
 - systemctl enable docker
 - systemctl start docker
 - /root/vuls/vuls-build.sh
 - rm /etc/cron.daily/0yum-daily.cron
 - systemctl enable yum-cron

write_files:
 - encoding: b64
   content: ${docker-logrotate}
   owner: root:root
   path: /etc/logrotate.d/docker
   permissions: '0644'
 - encoding: b64
   content: ${yum-cron-security-conf}
   owner: root:root
   path: /etc/yum/yum-cron-security.conf
   permissions: '0644'
 - encoding: b64
   content: ${yum-security-cron}
   owner: root:root
   path: /etc/cron.daily/0yum-security.cron
   permissions: '0744'
 - encoding: b64
   content: ${yum-clean-cron}
   owner: root:root
   path: /etc/cron.daily/1yum-clean.cron
   permissions: '0744'
 - encoding: b64
   content: ${vuls-cron}
   owner: root:root
   path: /etc/cron.daily/2vuls.cron
   permissions: '0744'
 - encoding: b64
   content: ${remove-unused-docker-data-cron}
   owner: root:root
   path: /etc/cron.daily/3remove-unused-docker-data.cron
   permissions: '0744'
 - encoding: b64
   content: ${post-yum-security-cron}
   owner: root:root
   path: /etc/cron.daily/zzzpost-yum-security.cron
   permissions: '0744'
 - encoding: b64
   content: ${gost-patch}
   owner: root:root
   path: /root/vuls/gost.patch
   permissions: '0644'
 - encoding: b64
   content: ${vuls-patch}
   owner: root:root
   path: /root/vuls/vuls.patch
   permissions: '0644'
 - encoding: b64
   content: ${sockguard-patch}
   owner: root:root
   path: /root/vuls/sockguard.patch
   permissions: '0644'
 - encoding: b64
   content: ${vuls-build-sh}
   owner: root:root
   path: /root/vuls/vuls-build.sh
   permissions: '0744'
 - encoding: b64
   content: ${vuls-fetch-sh}
   owner: root:root
   path: /root/vuls/vuls-fetch.sh
   permissions: '0744'
 - encoding: b64
   content: ${vuls-sh}
   owner: root:root
   path: /root/vuls/vuls.sh
   permissions: '0744'
 - encoding: b64
   content: ${vuls-config-slack}
   owner: root:root
   path: /root/vuls/config.slack.toml
   permissions: '0644'

power_state:
 delay: now
 mode: reboot
 timeout: 30
 condition: true
