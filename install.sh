#!/bin/bash

set -x
set -e

RELEASEURL="https://api.github.com/repos/snappyflow/apm-agent/releases/latest"
AGENTDIR="/opt/sfagent"
ID=`cat /etc/os-release | grep -w "ID" | cut -d"=" -f2 | tr -d '"'`

install_fluent_bit()
{

if [ "$ID" = "debian" ] || [ "$ID" = "ubuntu" ]; then
CODENAME=`cat /etc/os-release | grep -w "VERSION_CODENAME" | cut -d"=" -f2 | tr -d '"'`
curl -sOL https://packages.fluentbit.io/fluentbit.key;
apt-key add fluentbit.key
apt-add-repository "deb https://packages.fluentbit.io/$ID/$CODENAME $CODENAME main"
apt-get update
apt-get install -y td-agent-bit
systemctl enable td-agent-bit
systemctl start td-agent-bit
fi

if [ "$ID" = "centos" ]; then
VERSION=`cat /etc/os-release | grep -w "VERSION_ID" | cut -d"=" -f2 | tr -d '"'`
cat > /etc/yum.repos.d/td-agent-bit.repo <<EOF
[td-agent-bit]
name = TD Agent Bit
baseurl = http://packages.fluentbit.io/centos/$VERSION
gpgcheck=1
gpgkey=http://packages.fluentbit.io/fluentbit.key
enabled=1
EOF
yum install -y td-agent-bit wget
systemctl enable td-agent-bit
systemctl start td-agent-bit
fi

}

install_apm_agent()
{

ARCH=`uname -m`
rm -rf checksum* sfagent*
curl -sL $RELEASEURL \
| grep -w "browser_download_url" \
| cut -d":" -f 2,3 \
| tr -d '"' \
| xargs wget -q 
ls -l sfagent* checksum*
tar -zxvf sfagent*linux_$ARCH.tar.gz sfagent
mkdir -p $AGENTDIR
mv sfagent $AGENTDIR

cat > /etc/systemd/system/sfagent-config.service <<EOF
[Unit]
Description=snappyflow apm service
ConditionPathExists=!$AGENTDIR/config.yaml
After=network.target
 
[Service]
Type=oneshot

WorkingDirectory=$AGENTDIR
ExecStartPre=/bin/mkdir -p /var/log/sfagent
ExecStartPre=/bin/chmod 755 /var/log/sfagent
ExecStart=$AGENTDIR/sfagent -generate-config -file-name $AGENTDIR/config.yaml

StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=sfagent
 
[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/sfagent.service <<EOF
[Unit]
Description=snappyflow apm service
ConditionPathExists=$AGENTDIR/sfagent
After=network.target
 
[Service]
Type=simple
Restart=on-failure
RestartSec=10

WorkingDirectory=$AGENTDIR
ExecStartPre=/bin/mkdir -p /var/log/sfagent
ExecStartPre=/bin/chmod 755 /var/log/sfagent
ExecStart=$AGENTDIR/sfagent -config $AGENTDIR/config.yaml

StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=sfagent
 
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable sfagent-config
systemctl start sfagent-config
systemctl enable sfagent
systemctl start sfagent

}

pushd /tmp
install_fluent_bit
install_apm_agent
popd

