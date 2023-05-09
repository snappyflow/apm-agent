#!/bin/bash

set -x
set -e

FORWARDERDIR="/opt/sfagent/otel-trace-data-forwarder"
SERVICEFILE="/etc/systemd/system/otel-data-forwarder.service"


uninstall_apm_agent()
{
if [ -f "$SERVICEFILE" ];
then
    echo "remove otel-data-forwarder service"
    systemctl stop otel-data-forwarder
    systemctl disable otel-data-forwarder
    rm -f /etc/systemd/system/otel-data-forwarder.service
    systemctl daemon-reload 
fi
rm -rf  $FORWARDERDIR
rm -rf /var/log/sfagent

}

uninstall_services()
{

uninstall_apm_agent
#uninstall_fluent_bit
#uninstall_jcmd

}

oldpath=`pwd`
cd /tmp
uninstall_services
cd $oldpath
