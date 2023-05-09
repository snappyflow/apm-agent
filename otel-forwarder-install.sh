#!/bin/bash

# set -x
set -e
set -o pipefail

SHOULD_UPGRADE=0
SHOW_HELP=0
INCLUDE_PATHS=""
RELEASEURL="https://github.com/snappyflow/apm-agent/releases/download/opentelemetry-trace-forwarder/otel-trace-data-forwarder.tar.gz"
AGENTDIR="/opt/sfagent"
ID=$(grep -w "ID" /etc/os-release | cut -d"=" -f2 | tr -d '"')
SERVICEFILE="/etc/systemd/system/otel-data-forwarder.service"
DEFAULTPATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ENV_VARS=""
INITFILE="/etc/init.d/otel-data-forwarder"
ARCH=$(uname -m)
SYSTEM_TYPE=$(ps --no-headers -o comm 1)
AGENT_CERT="$AGENTDIR/certs/sfagent.pem"
AGENT_CERT_KEY="$AGENTDIR/certs/sfagent-key.pem"

logit()
{
    echo "[$(date +%d/%m/%Y-%T)] - ${*}"
}

ensure_system_packages()
{   
    logit "install required system packages"
    if [ "$ID" = "debian" ] || [ "$ID" = "ubuntu" ]; then
        apt install -qy curl wget &>/dev/null
    fi
    if [ "$ID" = "centos" ]; then
        yum install -y curl wget &>/dev/null
    fi
}

configure_logrotate_flb()
{
    logit "configure logrotate for fluent-bit"
    cat > /etc/logrotate.d/otel-data-forwarder << EOF
/var/log/otel-data-forwarder.log {
	daily
	dateext
	missingok
	copytruncate
	notifempty
	compress
	rotate 7
}
EOF
  logit "configure logrotate for fluent-bit completed"
}

install_or_upgrade_otel_data_forwarder()
{
    rm -rf $AGENTDIR/otel-trace-data-forwarder
    mkdir -p $AGENTDIR
    logit "download otel data forwarder"
    wget $RELEASEURL
    tar -xvf otel-trace-data-forwarder.tar.gz
    mv otel-trace-data-forwarder/ $AGENTDIR
    # create env file 
    create_env_file
    chown -R root:root /opt/sfagent/otel-trace-data-forwarder
    if [ "$SYSTEM_TYPE" = "systemd" ]; then
        create_forwarder_service
    else
        create_forwarder_init_service
    fi
    # restart sfagent
    if [ "$SYSTEM_TYPE" = "systemd" ]; then
        systemctl restart otel-data-forwarder.service
    else
        service otel-data-forwarder restart
    fi
    logit "install sfagent completed"
}

create_env_file()
{
    logit "create $AGENTDIR/otel-trace-data-forwarder/env.conf file"
    touch $AGENTDIR/otel-trace-data-forwarder/env.conf

    logit "environment PATH=$DEFAULTPATH"
    echo "PATH=$DEFAULTPATH" > $AGENTDIR/otel-trace-data-forwarder/env.conf

    if [ -n "$ENV_VARS" ]
    then
        logit "append env vars to $AGENTDIR/otel-trace-data-forwarder/env.conf"
        IFS=","
        for v in $ENV_VARS
        do
            echo $v >> $AGENTDIR/otel-trace-data-forwarder/env.conf
        done
    fi
}

create_forwarder_service()
{

logit "create otel-data-forwarder service"
cat > "$SERVICEFILE" <<EOF
[Unit]
Description=Opentelemetry data forwarder service
ConditionPathExists=$AGENTDIR/otel-trace-data-forwarder/otel-data-forwarder
After=network.target

[Service]
Type=simple
Restart=on-failure
RestartSec=10
WorkingDirectory=$AGENTDIR/otel-trace-data-forwarder/
EnvironmentFile=-$AGENTDIR/otel-trace-data-forwarder/env.conf
ExecStartPre=/bin/mkdir -p /var/log/sfagent
ExecStartPre=/bin/chmod 755 /var/log/sfagent
ExecStart=/bin/bash -c -e "/opt/sfagent/otel-trace-data-forwarder/otel-data-forwarder"

StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=sfagent

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
logit "enable otel-data-forwarder service"
systemctl enable otel-data-forwarder

}

create_forwarder_init_service()
{

logit "create otel-data-forwarder init.d file"
cat > "$INITFILE" <<'EOF'
#!/bin/bash
# otel-data-forwarder daemon
# chkconfig: - 20 80
# description: EC2 instance otel-data-forwarder agent
# processname: otel-data-forwarder

DAEMON_PATH="/opt/sfagent/otel-trace-data-forwarder"

NAME=otel-data-forwarder
DESC="My daemon description"
PIDFILE=/var/run/$NAME.pid
SCRIPTNAME=/etc/init.d/otel-data-forwarder

LOG_PATH=/var/log/sfagent/otel-data-forwarder.log

DAEMON=/opt/sfagent/otel-trace-data-forwarder//otel-data-forwarder

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 {start|stop|restart}"
    exit 1
else
    COMMAND="$1"
fi

case $COMMAND in
start)
        printf "%-50s" "Starting $NAME..."
        if [[ -f $PIDFILE ]]; then
                PID=`cat $PIDFILE`
                if [[ "`ps axf | grep ${PID} | grep -v grep`" ]]; then
                        echo "otel-data-forwarder is already running"
                        exit 0
                fi
        fi
        cd $DAEMON_PATH
        CMD="$DAEMON > /dev/null 2>&1"
        echo $CMD
        $CMD &
        if [ $? -eq 0 ]; then
                printf "%s\n" "Ok"
                echo $! > $PIDFILE
        else
                printf "%s\n" "Fail. Check logs $LOG_PATH"
                exit 1
        fi
        CMD1="update-rc.d otel-data-forwarder defaults"
        echo $CMD1
        $CMD1 &
        if [ $? -eq 0 ]; then
                printf "\n" "symbolic link added for otel-data-forwarder"
        else
                printf "%s\n" "Failed while adding symbolic link for otel-data-forwarder. Check logs $LOG_PATH"
                exit 1
        fi
;;
status)
        printf "%-50s" "Checking $NAME..."
        if [[ -f $PIDFILE ]]; then
                PID=`cat $PIDFILE`
                if [[ -z "`ps axf | grep ${PID} | grep -v grep`" ]]; then
                        printf "%s\n" "Process dead but pidfile exists"
                else
                        echo "Running"
                fi
        else
                printf "%s\n" "Service not running failed"
        fi
;;
stop)
        printf "%-50s" "Stopping $NAME"
        if [[ -f $PIDFILE ]]; then
                PID=`cat $PIDFILE`
                kill -HUP $PID
                printf "%s\n" "Ok"
                rm -f $PIDFILE
                exit 0
        else
                printf "%s\n" "already stopped"
                exit 0
        fi
;;

restart)
        $0 stop
        $0 start
;;

*)
        echo "Usage: $0 {status|start|stop|restart}"
        exit 1
esac

EOF

chmod +x "$INITFILE"
logit "otel-data-forwarder init script created"
}

print_usage()
{
    echo ""
    echo "usage of otel-forwarder-install.sh"
    echo "  ./otel-forwarder-install.sh [-h|--help][-u|--upgrade][--paths \"path1,path2\"][--env \"ENV_VAR1=value1,ENV_VAR2=value2\"]"
    echo ""
    echo "  -h|--help    show usage information"
    echo "  -u|--upgrade upgrade installed sfagent"
    echo "  --env        comma seperated list of Environemt variables"
    echo "                 ex: \"HTTP_PROXY=http://proxy.example.com,HTTPS_PROXY=https://proxy.example.com\""
    echo ""
    echo "examples:"
    echo "  ./otel-forwarder-install.sh"
    echo "  ./otel-forwarder-install.sh --upgrade"
    echo "  ./otel-forwarder-install.sh --upgrade --paths \"/opt/jdk1.8.0_211/bin,/opt/jdk1.8.0_211/jre/bin\""
    echo "  ./otel-forwarder-install.sh --env \"HTTP_PROXY=http://proxy.example.com,HTTPS_PROXY=https://proxy.example.com\""
    echo ""
}

UNKNOWN=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    --env)
    ENV_VARS="$2"
    shift
    shift
    ;;
    -h|--help)
    SHOW_HELP=1
    shift
    ;;
    -u|--upgrade)
    SHOULD_UPGRADE=1
    shift
    ;;
    *)
    UNKNOWN+=("$1")
    shift
    ;;
esac
done

if [ -n "$UNKNOWN" ]; then 
    logit "ERROR: unknown arguments: $UNKNOWN"
    print_usage
    exit 128
fi

if [ "$SHOW_HELP" -eq 1 ]; then
    print_usage
    exit 0
fi

oldpath=$(pwd)
tmp_dir=$(mktemp -d -t installsfagent-XXXXXXXXXX)
cd "$tmp_dir"

if [ "$EUID" -ne 0 ]; then
    logit "Need root previlege to proceed with installation."
    exit 0
fi


if [ "$SHOULD_UPGRADE" -eq 1 ];then
    ensure_system_packages
    install_or_upgrade_otel_data_forwarder
else
    ensure_system_packages
    install_or_upgrade_otel_data_forwarder
fi

cd "$oldpath"
rm -rf "$tmp_dir"

sleep 1
logit "Done"
exit 0