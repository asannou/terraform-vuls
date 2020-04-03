#cloud-config

timezone: "Asia/Tokyo"

packages:
 - amazon-ssm-agent
 - yum-cron-security
 - aws-cli

runcmd:
 - rm /etc/init/ecs.conf
 - yum -y update
 - start amazon-ssm-agent
 - chkconfig yum-cron on

write_files:
 - encoding: b64
   content: ${docker-logrotate}
   owner: root:root
   path: /etc/logrotate.d/docker
   permissions: '0644'
 - encoding: b64
   content: ${post-yum-security-cron}
   owner: root:root
   path: /etc/cron.daily/zzzpost-yum-security.cron
   permissions: '0744'
 - encoding: b64
   content: ${yum-clean-cron}
   owner: root:root
   path: /etc/cron.weekly/yum-clean.cron
   permissions: '0744'
 - encoding: b64
   content: ${remove-unused-docker-data-cron}
   owner: root:root
   path: /etc/cron.weekly/remove-unused-docker-data.cron
   permissions: '0744'
 - encoding: b64
   content: ${vuls-sh}
   owner: root:root
   path: /root/vuls/vuls.sh
   permissions: '0744'
 - encoding: b64
   content: ${vuls-config}
   owner: root:root
   path: /root/vuls/config.toml.default
   permissions: '0644'
 - encoding: b64
   content: ${vuls-cron}
   owner: root:root
   path: /etc/cron.daily/vuls.cron
   permissions: '0744'

power_state:
 delay: now
 mode: reboot
 timeout: 30
 condition: true
