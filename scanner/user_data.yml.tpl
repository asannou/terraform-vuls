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
 - curl -L -o /root/vuls/awscurl-lite https://gist.github.com/asannou/3a86f9e85275f99bd1f9a5432adf2408/raw/awscurl-lite
 - chmod +x /root/vuls/awscurl-lite

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
   content: ${vuls-privatelink-sh}
   owner: root:root
   path: /root/vuls/vuls-privatelink.sh
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
