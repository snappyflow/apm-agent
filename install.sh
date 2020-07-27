#!/bin/bash

#set -x
set -e

RELEASEURL="https://api.github.com/repos/snappyflow/apm-agent/releases/latest"
FLUENTBIT_x86_64="https://github.com/snappyflow/apm-agent/releases/download/fluentbit.tar.gz.1.9/fluentbit.tar.gz"
JAVA_AGENT_x86_64="https://github.com/snappyflow/apm-agent/releases/download/sf-trace-java-agent-1.16.1/sftrace-agent-1.16.1.tar.gz"
AGENTDIR="/opt/sfagent"
TDAGENTCONFDIR="/etc/td-agent-bit"
ID=`cat /etc/os-release | grep -w "ID" | cut -d"=" -f2 | tr -d '"'`
SERVICEFILE="/etc/systemd/system/sfagent.service"


configure_logrotate_flb()
{
    echo "Configure logrotate fluent-bit started"
    if [ "$ID" = "debian" ] || [ "$ID" = "ubuntu" ]; then
        apt install -qy logrotate &>/dev/null
    fi

    if [ "$ID" = "centos" ]; then
        yum install -y logrotate &>/dev/null
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
  echo "Configure logrotate fluent-bit completed"
}


install_fluent_bit()
{
    echo "                                           "
    echo "Install fluent-bit started "
    if [ "$ID" = "debian" ] || [ "$ID" = "ubuntu" ]; then
         apt-get install -y -q wget curl
    fi
    if [ "$ID" = "centos" ]; then
        yum install -y wget curl
    fi
    wget $FLUENTBIT_x86_64
    mkdir -p /opt/td-agent-bit/bin && mkdir -p /etc/td-agent-bit/
    tar -zxvf fluentbit.tar.gz >/dev/null && mv -f fluent-bit /opt/td-agent-bit/bin/td-agent-bit && mv -f GeoLite2-City.mmdb $TDAGENTCONFDIR
    mv -f td-agent-bit.conf /etc/td-agent-bit/
    configure_logrotate_flb
    echo "Install fluent-bit completed"
    echo "                             "
}

install_java_agent()
{
    echo "                                           "
    echo "Install elastic java-agent started "
    wget $JAVA_AGENT_x86_64
    mkdir -p /opt/sfagent/sftrace/java
    tar -zxvf sftrace-agent-1.16.1.tar.gz >/dev/null && mv -f sftrace-agent-1.16.1.jar /opt/sfagent/sftrace/java
    echo "Install elastic java-agent completed"
    echo "                             "
}

upgrade_fluent_bit()
{
    td_agent_bit_status=$(systemctl show -p ActiveState td-agent-bit | cut -d'=' -f2)
    if [ "$td_agent_bit_status" = "active" ];
    then
        systemctl stop td-agent-bit
        systemctl disable td-agent-bit
    fi
    wget $FLUENTBIT_x86_64
    tar -zxvf fluentbit.tar.gz >/dev/null && mv -f fluent-bit /opt/td-agent-bit/bin/td-agent-bit && mv -f GeoLite2-City.mmdb $TDAGENTCONFDIR
    mv -f td-agent-bit.conf /etc/td-agent-bit
    echo "Upgrade fluent-bit binary completed "
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
    ls -l sfagent* checksum* >/dev/null
    tar -zxvf sfagent*linux_$ARCH.tar.gz >/dev/null
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
    echo "Upgrading apm agent binaries completed"
else
    echo "directory $AGENTDIR doesn't exists"
    install_services
fi

}

install_apm_agent()
{
    echo "                         "
    echo "Install APM Agent started"
    ARCH=`uname -m`
    rm -rf checksum* sfagent* mappings $AGENTDIR
    curl -sL $RELEASEURL \
    | grep -w "browser_download_url" \
    | cut -d":" -f 2,3 \
    | tr -d '"' \
    | xargs wget -q
    ls -l sfagent* checksum* >/dev/null
    tar -zxvf sfagent*linux_$ARCH.tar.gz >/dev/null
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
    echo "Install APM Agent completed"
    echo "                               "
}

check_jcmd_installation()
{
echo "                          "
echo "Checking jcmd installation"
if ! [ -x "$(command -v jcmd)" ]; then
  echo "Warning: jcmd is not installed. Java applications will not be detected automatically"
else
  echo "jcmd is installed"
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
install_java_agent

}

oldpath=`pwd`
#cd /tmp
tmp_dir=$(mktemp -d -t installsfagent-XXXXXXXXXX)
cd $tmp_dir

if [ "$1" = "upgrade" ];
then
    echo "Upgrading fluent-bit binary"
    upgrade_fluent_bit
    echo "Upgrading apm agent binaries"
    upgrade_apm_agent
else
    install_services
fi
cd $oldpath
rm -rf $tmp_dir
