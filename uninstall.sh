#!/bin/bash

set -x
set -e

AGENTDIR="/opt/sfagent"
TDAGENTCONFDIR="/etc/td-agent-bit"
ID=`cat /etc/os-release | grep -w "ID" | cut -d"=" -f2 | tr -d '"'`

uninstall_jcmd()
{

if [ "$ID" = "debian" ] || [ "$ID" = "ubuntu" ]; then
apt-get purge --auto-remove -y openjdk-9-jdk-headless
fi

if [ "$ID" = "centos" ]; then
yum remove -y java-1.8.0-openjdk-devel
fi

}

uninstall_fluent_bit()
{

if [ "$ID" = "debian" ] || [ "$ID" = "ubuntu" ]; then
apt-get purge --auto-remove -y mmdb-bin
apt-get purge --auto-remove -y td-agent-bit
fi

if [ "$ID" = "centos" ]; then
systemctl stop td-agent-bit

yum remove -y td-agent-bit
rm -rf $TDAGENTCONFDIR
rm /etc/yum.repos.d/td-agent-bit.repo
fi

}

uninstall_apm_agent()
{

systemctl stop sfagent
rm -rf  $AGENTDIR
rm -rf /var/log/sfagent
rm /etc/systemd/system/sfagent.service

}

uninstall_services()
{

uninstall_fluent_bit
uninstall_jcmd
uninstall_apm_agent

}

oldpath=`pwd`
cd /tmp
uninstall_services
cd $oldpath

