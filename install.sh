#!/bin/bash

set -x
set -e

RELEASEURL="https://api.github.com/repos/snappyflow/apm-agent/releases/latest"
FLUENTBIT_x86_64="https://github.com/snappyflow/apm-agent/releases/download/fluentbit.tar.gz.1.9/fluentbit.tar.gz"
AGENTDIR="/opt/sfagent"
TDAGENTCONFDIR="/etc/td-agent-bit"
ID=`cat /etc/os-release | grep -w "ID" | cut -d"=" -f2 | tr -d '"'`
SERVICEFILE="/etc/systemd/system/sfagent.service"


configure_logrotate_flb()
{

    if [ "$ID" = "debian" ] || [ "$ID" = "ubuntu" ]; then
        apt install -y logrotate
    fi

    if [ "$ID" = "centos" ]; then
        yum install -y logrotate
    fi

    cat > /etc/logrotate.d/td-agent-bit << EOF
/var/log/td-agent-bit.log {
	daily
	dateext
	missingok
	copytruncate
	notifempty
	compress
	rotate 7
}
EOF

}


install_fluent_bit()
{
    if [ "$ID" = "debian" ] || [ "$ID" = "ubuntu" ]; then
         apt-get install -y wget curl
    fi
    if [ "$ID" = "centos" ]; then
        yum install -y wget curl
    fi
    wget $FLUENTBIT_x86_64
    mkdir -p /opt/td-agent-bit/bin && mkdir -p /etc/td-agent-bit/
    tar -zxvf fluentbit.tar.gz && mv -f fluent-bit /opt/td-agent-bit/bin && mv -f GeoLite2-City.mmdb $TDAGENTCONFDIR
    mv -f td-agent-bit.conf /etc/td-agent-bit/
    mv -f td-agent-bit.service /etc/systemd/system/td-agent-bit.service
    systemctl daemon-reload
    systemctl enable td-agent-bit
configure_logrotate_flb
}

upgrade_apm_agent()
{

if [ -d "$AGENTDIR" ]; then
    if [ -f "$SERVICEFILE" ]; then
        echo "Stop sfagent"
        systemctl stop sfagent
    fi
    ARCH=`uname -m`
    echo "Backingup config.yaml"
    cp -f $AGENTDIR/config.yaml _config_backup.yaml
    rm -rf checksum* sfagent* mappings
    curl -sL $RELEASEURL \
    | grep -w "browser_download_url" \
    | cut -d":" -f 2,3 \
    | tr -d '"' \
    | xargs wget -q 
    ls -l sfagent* checksum*
    tar -zxvf sfagent*linux_$ARCH.tar.gz
    mkdir -p $AGENTDIR/certs
    mv -f sfagent $AGENTDIR
    mv -f jolokia.jar $AGENTDIR
    mv -f mappings/* $AGENTDIR/mappings/
    mv -f scripts/* $AGENTDIR/scripts/
    mv -f certs/* $AGENTDIR/certs/
    mv -f config.yaml.sample $AGENTDIR/config.yaml.sample
    echo "Copying back config.yaml"
    cp -f _config_backup.yaml $AGENTDIR/config.yaml
    chown -R root:root /opt/sfagent
    create_sfagent_service
    systemctl restart sfagent
else
    echo "directory $AGENTDIR doesn't exists"
    install_services
fi

}

install_apm_agent()
{

    ARCH=`uname -m`
    rm -rf checksum* sfagent* mappings $AGENTDIR
    curl -sL $RELEASEURL \
    | grep -w "browser_download_url" \
    | cut -d":" -f 2,3 \
    | tr -d '"' \
    | xargs wget -q 
    ls -l sfagent* checksum*
    tar -zxvf sfagent*linux_$ARCH.tar.gz
    mkdir -p $AGENTDIR
    mkdir -p $AGENTDIR/mappings
    mkdir -p $AGENTDIR/scripts
    mkdir -p $AGENTDIR/certs
    mv sfagent $AGENTDIR
    mv jolokia.jar $AGENTDIR
    mv mappings $AGENTDIR/.
    mv scripts $AGENTDIR/.
    mv certs $AGENTDIR/.
    mv config.yaml.sample $AGENTDIR/config.yaml.sample
    cat > $AGENTDIR/config.yaml <<EOF
agent:
metrics:
logging:
tags:
key:
EOF

    chown -R root:root /opt/sfagent
    create_sfagent_service
    systemctl restart sfagent

}

check_jcmd_installation()
{

echo "Checking jcmd installation"
if ! [ -x "$(command -v jcmd)" ]; then
  echo "Error: jcmd is not installed. It is Needed for service discovery"
else
  echo "jcmd installed"
fi

}

create_sfagent_service()
{
echo "create sfagent service file"
cat > "$SERVICEFILE" <<EOF
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
ExecStart=$AGENTDIR/sfagent -config-file $AGENTDIR/config.yaml
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=sfagent

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable sfagent

}

install_services()
{

install_fluent_bit
check_jcmd_installation
install_apm_agent

}

oldpath=`pwd`
cd /tmp

if [ "$1" = "upgrade" ];
then
    echo "Upgrading apm agent binaries"
    upgrade_apm_agent
else
    install_services
fi
cd $oldpath

