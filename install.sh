#!/bin/bash

# set -x
set -e
set -o pipefail

# Default values of arguments
SHOULD_UPGRADE=0
SHOW_HELP=0
INCLUDE_PATHS=""
INSTALL_MAT=0
RELEASEURL="https://api.github.com/repos/snappyflow/apm-agent/releases/latest"
SFTRACE_AGENT_x86_64="https://github.com/snappyflow/apm-agent/releases/download/latest/sftrace-agent.tar.gz"
FLUENT_CENTOS_6_BUILD="https://github.com/snappyflow/apm-agent/releases/download/centos6-td-agent-bit/fluentbit.tar.gz"
AGENTDIR="/opt/sfagent"
AGENTDIR_BKP="/opt/sfagent_bkp"
TDAGENTCONFDIR="/etc/td-agent-bit"
ID=$(grep -w "ID" /etc/os-release | cut -d"=" -f2 | tr -d '"')
SERVICEFILE="/etc/systemd/system/sfagent.service"
DEFAULTPATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ENV_VARS=""
INITFILE="/etc/init.d/sfagent"
ARCH=$(uname -m)
SYSTEM_TYPE=$(ps --no-headers -o comm 1)
AGENT_CERT="$AGENTDIR/certs/sfagent.pem"
AGENT_CERT_KEY="$AGENTDIR/certs/sfagent-key.pem"

logit() 
{
    echo "[$(date +%d/%m/%Y-%T)] - ${*}"
}

check_nc_installation()
{
    command -v "$1" >/dev/null 2>&1
}

ensure_system_packages()
{   
    logit "install required system packages"
    if [ "$ID" = "debian" ] || [ "$ID" = "ubuntu" ]; then
        apt install -qy curl wget netcat logrotate sysstat &>/dev/null
        if check_nc_installation "netcat"; then
            logit "netcat (nc) command is installed."
        else
            logit "installing netcat command"
            apt install netcat &>/dev/null
            if check_nc_installation "netcat" ; then
                logit "Unable to install netcat command. Please install it manually"
            fi
        fi
    fi
    if [ "$ID" = "centos" ] || [ "$ID" = "amzn" ]; then
        yum install -y curl wget nc logrotate sysstat &>/dev/null
        if check_nc_installation "nc"; then
            logit "netcat (nc) command is installed."
        else
            logit "installing netcat command"
            yum install -y nc &>/dev/null
            if check_nc_installation "nc" ; then
                logit "Unable to install nc command. Please install it manually"
            fi
        fi
    fi
}

configure_logrotate_flb()
{
    logit "configure logrotate for fluent-bit"
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
  logit "configure logrotate for fluent-bit completed"
}


install_fluent_bit()
{    
    if [ "$SYSTEM_TYPE" = "systemd" ] &&  [ "$ARCH" != "aarch64" ] ; then
        logit "download latest fluent-bit release $ARCH"
        curl -sL https://api.github.com/repos/snappyflow/apm-agent/releases?per_page=100 \
        | grep -w "browser_download_url"|grep fluentbit-amd \
        | head -n 1 \
        | cut -d":" -f 2,3 \
        | tr -d '"' \
        | xargs wget -q 
        logit "download latest fluent-bit release done"
    elif [ "$SYSTEM_TYPE" = "systemd" ] && [ "$ARCH" = "aarch64" ]; then
        logit "download latest fluent-bit release $ARCH"
        curl -sL https://api.github.com/repos/snappyflow/apm-agent/releases?per_page=100 \
        | grep -w "browser_download_url"|grep fluentbit-arm \
        | head -n 1 \
        | cut -d":" -f 2,3 \
        | tr -d '"' \
        | xargs wget -q 
        logit "download latest arm64 fluent-bit release done"
    else
        logit "download centos 6 fluent-bit release"
        wget -q $FLUENT_CENTOS_6_BUILD
        logit "download centos 6 fluent-bit release done"
    fi
    mkdir -p /opt/td-agent-bit/bin && mkdir -p /etc/td-agent-bit/
    tar -zxvf fluentbit.tar.gz >/dev/null && mv -f fluent-bit /opt/td-agent-bit/bin/td-agent-bit && mv -f GeoLite2-City.mmdb $TDAGENTCONFDIR
    [ -f url-normalizer ] && mv -f url-normalizer /opt/td-agent-bit/bin/
    [ -f ldap-parser ] && mv -f ldap-parser /opt/td-agent-bit/bin/
    [ -f uaparserserver ] && mv -f uaparserserver /opt/td-agent-bit/bin/
    [ -f message-formatter ] && mv -f message-formatter /opt/td-agent-bit/bin/
    [ -f airflow-goals-parser ] && mv -f airflow-goals-parser /opt/td-agent-bit/bin/
    mv -f td-agent-bit.conf /etc/td-agent-bit/
    configure_logrotate_flb
    logit "install fluent-bit completed"
}

install_sftrace_agent()
{
    logit "install sftrace java-agent and python-agent"
    wget -q $SFTRACE_AGENT_x86_64
    tar -zxvf sftrace-agent.tar.gz >/dev/null && mv -f sftrace /opt/sfagent && mv -f /opt/sfagent/sftrace/sftrace /bin && mv -f /opt/sfagent/sftrace/java/sftrace /opt/sfagent/sftrace
    logit "install sftrace java-agent and python-agent completed"
}

upgrade_fluent_bit()
{
    #td_agent_bit_status=$(systemctl show -p ActiveState td-agent-bit | cut -d'=' -f2)
    #if [ "$td_agent_bit_status" = "active" ];
    #then
    #    systemctl stop td-agent-bit
    #    systemctl disable td-agent-bit
    #fi
    [ -d /opt/td-agent-bit/bin_bkp ] && logit "remove old backup directories /opt/td-agent-bit/bin_bkp" && rm -rf /opt/td-agent-bit/bin_bkp
    cp -R /opt/td-agent-bit/bin /opt/td-agent-bit/bin_bkp
    if [ "$SYSTEM_TYPE" = "systemd" ] && [ "$ARCH" != "aarch64" ]; then
        logit "download latest fluent-bit release for $ARCH"
        curl -sL https://api.github.com/repos/snappyflow/apm-agent/releases?per_page=100 \
        | grep -w "browser_download_url"|grep fluentbit-amd \
        | head -n 1 \
        | cut -d":" -f 2,3 \
        | tr -d '"' \
        | xargs wget -q 
        logit "download latest fluent-bit release done"
    elif [ "$SYSTEM_TYPE" = "systemd" ] && [ "$ARCH" = "aarch64" ]; then
        logit "download latest fluent-bit release for $ARCH"
        curl -sL https://api.github.com/repos/snappyflow/apm-agent/releases?per_page=100 \
        | grep -w "browser_download_url"|grep fluentbit-arm \
        | head -n 1 \
        | cut -d":" -f 2,3 \
        | tr -d '"' \
        | xargs wget -q 
        logit "download latest arm64 fluent-bit release done"
    else
        logit "download centos 6 build for fluent-bit"
        wget -q $FLUENT_CENTOS_6_BUILD
        logit "download centos 6 fluent-bit release done"
    fi
    tar -zxvf fluentbit.tar.gz >/dev/null && mv -f fluent-bit /opt/td-agent-bit/bin/td-agent-bit && mv -f GeoLite2-City.mmdb $TDAGENTCONFDIR
    [ -f url-normalizer ] && mv -f url-normalizer /opt/td-agent-bit/bin/
    [ -f ldap-parser ] && mv -f ldap-parser /opt/td-agent-bit/bin/
    [ -f uaparserserver ] && mv -f uaparserserver /opt/td-agent-bit/bin/
    [ -f message-formatter ] && mv -f message-formatter /opt/td-agent-bit/bin/
    [ -f airflow-goals-parser ] && mv -f airflow-goals-parser /opt/td-agent-bit/bin/
    mv -f td-agent-bit.conf /etc/td-agent-bit
    logit "upgrade fluent-bit completed"
}

install_eclipse_mat()
{   
    logit "checking Eclipse MAT installed"
    DIR="/opt/sfagent/Eclipse_Mat_File"
    MAT_URL="https://github.com/snappyflow/apm-agent/raw/master/MemoryAnalyzer-1.10.0.20200225-linux.gtk.x86_64.zip"
    if [ -d "$DIR" ]; then
        # Take action if $DIR exists. #
        logit "eclipse MAT is already installed in ${DIR}..."
    else
        logit "downloading Eclipse MAT"
        mkdir -p /opt/sfagent/Eclipse_Mat_File
        wget -q -O /opt/sfagent/Eclipse_Mat_MemoryAnalyzer.zip $MAT_URL && unzip /opt/sfagent/Eclipse_Mat_MemoryAnalyzer.zip -d /opt/sfagent/Eclipse_Mat_File/
        logit "Eclipse MAT is successfully installed"
    fi     
}

upgrade_sftrace_agent()
{
    wget -q $SFTRACE_AGENT_x86_64
    logit "download latest sftrace agent done"
    [ -f $AGENTDIR/sftrace/java/elasticapm.properties ] && mv -f /opt/sfagent/sftrace/java/elasticapm.properties .
    rm -rf /opt/sfagent/sftrace
    rm -rf /bin/sftrace
    tar -zxvf sftrace-agent.tar.gz >/dev/null && mv -f sftrace /opt/sfagent && mv -f /opt/sfagent/sftrace/sftrace /bin && mv -f /opt/sfagent/sftrace/java/sftrace /opt/sfagent/sftrace
    [ -f elasticapm.properties ] && mv -f elasticapm.properties /opt/sfagent/sftrace/java/
    logit "upgrade sftrace java-agent and python-agent completed"
}

upgrade_apm_agent()
{
    buildinfo=$($AGENTDIR/sfagent --version | tr '\n' ',')
    logit "existing buildinfo $buildinfo"

    if [ -d "$AGENTDIR" ]; then
        if [ -f "$SERVICEFILE" ]; then
            logit "stop sfagent service"
            systemctl stop sfagent.service
        fi
        [ -d $AGENTDIR_BKP ] && logit "remove old backup directories $AGENTDIR_BKP" && rm -rf $AGENTDIR_BKP
        logit "backup existing build"
        cp -R $AGENTDIR $AGENTDIR_BKP
        logit "backup config.yaml, env.conf and customer scripts"
        cp -f $AGENTDIR/config.yaml _config_backup.yaml && logit "backup $AGENTDIR/config.yaml"
        #Creation of normalization dir to be removed in future once older agents are upgraded
        mkdir -p $AGENTDIR/normalization
        [ -f $AGENTDIR/normalization/config.yaml ] && cp $AGENTDIR/normalization/config.yaml _norm_config_backup.yaml && logit "backup $AGENTDIR/normalization/config.yaml"
        [ -f $AGENTDIR/mappings/custom_logging_plugins.yaml ] && cp $AGENTDIR/mappings/custom_logging_plugins.yaml _custom_logging_backup.yaml && logit "backup $AGENTDIR/mappings/custom_logging_plugins.yaml"
        [ -f $AGENTDIR/scripts/custom_scripts.lua ] && cp $AGENTDIR/scripts/custom_scripts.lua _custom_script_backup.yaml && logit "backup $AGENTDIR/scripts/custom_scripts.lua"
        [ -f $AGENTDIR/env.conf ] && cp $AGENTDIR/env.conf _env.conf && logit "backup $AGENTDIR/env.conf"
        rm -rf checksum* sfagent* mappings normalization
        logit "download latest sfagent release"
        curl -sL $RELEASEURL \
        | grep -w "browser_download_url" \
        | cut -d":" -f 2,3 \
        | tr -d '"' \
        | xargs wget -q 
        logit "download latest sfagent release done"
        CHECKSUM=$(grep "$ARCH" checksums.txt | sha256sum --check | grep OK)
        if [ ${#CHECKSUM} != 0 ]; then
            logit "checksum verification $CHECKSUM"
            ls -l sfagent* checksum* >/dev/null
            tar -zxvf sfagent*linux_$ARCH.tar.gz >/dev/null
            mkdir -p $AGENTDIR/certs
            mkdir -p $AGENTDIR/statsd_rules
            mv -f sfagent $AGENTDIR
            mv -f jolokia.jar $AGENTDIR
            mv -f mappings/* $AGENTDIR/mappings/
            mv -f scripts/* $AGENTDIR/scripts/
            mv -f certs/* $AGENTDIR/certs/
            mv -f statsd/* $AGENTDIR/statsd_rules/
            mv -f normalization/* $AGENTDIR/normalization/
            mv -f config.yaml.sample $AGENTDIR/config.yaml.sample
            
            logit "restore config.yaml, env.conf and customer scripts"
            cp -f _config_backup.yaml $AGENTDIR/config.yaml && logit "restore $AGENTDIR/config.yaml"
            [ -f _norm_config_backup.yaml ] && cp _norm_config_backup.yaml $AGENTDIR/normalization/config.yaml && logit "restore $AGENTDIR/normalization/config.yaml"
            [ -f _custom_logging_backup.yaml ] &&  cp _custom_logging_backup.yaml $AGENTDIR/mappings/custom_logging_plugins.yaml && logit "restore $AGENTDIR/mappings/custom_logging_plugins.yaml"
            [ -f _custom_script_backup.yaml ] && cp _custom_script_backup.yaml $AGENTDIR/scripts/custom_scripts.lua && logit "restore $AGENTDIR/scripts/custom_scripts.lua"
            [ -f _env.conf ] && cp _env.conf $AGENTDIR/env.conf && logit "restore $AGENTDIR/env.conf"
            chown -R root:root /opt/sfagent
            # create service files
            if [ "$SYSTEM_TYPE" = "systemd" ]; then
                create_sfagent_service
            else
                create_sfagent_init_script
            fi
            # restart sfagent
            logit "restart sfagent service"
            if [ "$SYSTEM_TYPE" = "systemd" ]; then
                systemctl restart sfagent.service
            else
                service sfagent restart
            fi
            # get agent status 
            if [ "$SYSTEM_TYPE" = "systemd" ]; then
                status=$(systemctl status sfagent.service)
            else
                status=$(service sfagent status)
            fi
            # revert to old build if agent is in failed state after upgrade
            if [[ $status == *"failed"* ]] ;then
                logit "upgarde sfagent failed"
                rm -rf $AGENTDIR
                mv $AGENTDIR_BKP $AGENTDIR
                rm -rf /opt/td-agent-bit/bin
                mv /opt/td-agent-bit/bin_bkp /opt/td-agent-bit/bin
                # restart sfagent
                if [ "$SYSTEM_TYPE" = "systemd" ]; then
                    systemctl restart sfagent.service
                else
                    service sfagent restart
                fi
                logit "upgrade sfagent failed reverted to old release"
                check_and_send_status "failed"
            else
                rm -rf $AGENTDIR_BKP
                rm -rf /opt/td-agent-bit/bin_bkp
                logit "upgrade sfagent completed"
                check_and_send_status "success"
            fi
        else
            logit "checksum verification failed $CHECKSUM"
        fi
    else
        logit "directory $AGENTDIR not found, installing agent"
        install_apm_agent
    fi
}

check_and_send_status()
{   
    if [ -e /tmp/upgrade_status.json ]
    then
        logit "automated upgrade sending upgarde status"
        status=$1
        logit "sfagent running response code $status" 
        if [ "$status" = "success" ]
        then
	    buildinfo=$($AGENTDIR/sfagent --version | tr '\n' ',')
            logit "upgraded buildinfo $buildinfo"
            sed -i "s/#STATUS/$1/g" /tmp/upgrade_status.json
            sed -i "s/#MESSAGE/$buildinfo/g" /tmp/upgrade_status.json
            sed -i "s/111122223333/$(($(date +%s%N)/1000000))/g" /tmp/upgrade_status.json
            sed -i "s/111122224444/$(($(date +%s%N)/1000000))/g" /tmp/upgrade_status.json
            # send data to forwarder
            while ! nc -z 127.0.0.1 8588; do
                logit "wait for forwarder to accept connection"
                sleep 5
            done
            response=$(curl -s --connect-timeout 10 -m 30 -XPOST -H "Accept: application/json" http://127.0.0.1:8588/ -d @/tmp/upgrade_status.json)
            logit "upgrade command status sent $response"
        else
            logit "sfagent not running"
        fi
    fi
}


install_apm_agent()
{
    rm -rf checksum* sfagent* mappings normalization $AGENTDIR
    logit "download latest sfagent release"
    curl -sL $RELEASEURL \
    | grep -w "browser_download_url" \
    | cut -d":" -f 2,3 \
    | tr -d '"' \
    | xargs wget -q
    logit "download latest sfagent release done"
    ls -l sfagent* checksum* >/dev/null
    CHECKSUM=$(grep $ARCH checksums.txt | sha256sum --check | grep OK)
    logit "checksum verification $CHECKSUM"
    tar -zxvf sfagent*linux_$ARCH.tar.gz >/dev/null
    mkdir -p $AGENTDIR
    mkdir -p $AGENTDIR/mappings
    mkdir -p $AGENTDIR/scripts
    mkdir -p $AGENTDIR/certs
    mkdir -p $AGENTDIR/normalization
    mkdir -p $AGENTDIR/statsd_rules
    mv sfagent $AGENTDIR
    mv jolokia.jar $AGENTDIR
    mv mappings $AGENTDIR/.
    mv scripts $AGENTDIR/.
    mv certs $AGENTDIR/.
    mv normalization $AGENTDIR/.
    mv statsd/* $AGENTDIR/statsd_rules
    mv config.yaml.sample $AGENTDIR/config.yaml.sample
    cat > $AGENTDIR/config.yaml <<EOF
agent:
metrics:
logging:
tags:
key:
EOF
    # create env file 
    create_env_file
    chown -R root:root /opt/sfagent
    if [ "$SYSTEM_TYPE" = "systemd" ]; then
        create_sfagent_service
    else
        create_sfagent_init_script
    fi
    # restart sfagent
    if [ "$SYSTEM_TYPE" = "systemd" ]; then
        systemctl restart sfagent.service
    else
        service sfagent restart
    fi
    logit "install sfagent completed"
}

check_jcmd_installation()
{
    logit "checking jcmd installation"
    if ! [ -x "$(command -v jcmd)" ]; then
        logit "Warning: jcmd is not installed. Java applications will not be detected automatically"
    else
        logit "jcmd is installed"
    fi
}

create_env_file()
{
    logit "create $AGENTDIR/env.conf file"
    touch $AGENTDIR/env.conf

    if [ -n "$INCLUDE_PATHS" ];
    then
        logit "extra paths to include in PATH - $INCLUDE_PATHS"
        IFS=","
        for v in $INCLUDE_PATHS
        do
            DEFAULTPATH="$DEFAULTPATH:$v"
        done
    fi
    logit "environment PATH=$DEFAULTPATH"
    echo "PATH=$DEFAULTPATH" > $AGENTDIR/env.conf

    if [ -n "$ENV_VARS" ]
    then
        logit "append env vars to $AGENTDIR/env.conf"
        IFS=","
        for v in $ENV_VARS
        do
            echo $v >> $AGENTDIR/env.conf
        done
    fi
}

create_sfagent_service()
{

logit "create sfagent service"
cat > "$SERVICEFILE" <<EOF
[Unit]
Description=snappyflow apm agent service
ConditionPathExists=$AGENTDIR/sfagent
After=network.target

[Service]
Type=simple
Restart=on-failure
RestartSec=10
WorkingDirectory=$AGENTDIR
EnvironmentFile=-$AGENTDIR/env.conf
ExecStartPre=/bin/mkdir -p /var/log/sfagent
ExecStartPre=/bin/chmod 755 /var/log/sfagent
ExecStartPre=/bin/bash -c -e "/opt/sfagent/sfagent -config-file /opt/sfagent/config.yaml -check-config"
ExecStart=/bin/bash -c -e "/opt/sfagent/sfagent -config-file /opt/sfagent/config.yaml"

StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=sfagent

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
logit "enable sfagent service"
systemctl enable sfagent

}

create_sfagent_init_script()
{

logit "create sfagent init.d file"
cat > "$INITFILE" <<'EOF'
#!/bin/bash
# sfagent daemon
# chkconfig: - 20 80
# description: EC2 instance SnappyFlow agent
# processname: sfagent

DAEMON_PATH="/opt/sfagent"

NAME=sfagent
DESC="My daemon description"
PIDFILE=/var/run/$NAME.pid
SCRIPTNAME=/etc/init.d/sfagent

LOG_PATH=/var/log/sfagent/sfagent.log

DAEMON=/opt/sfagent/sfagent
DAEMONOPTS="-config /opt/sfagent/config.yaml"

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
                        echo "sfagent is already running"
                        exit 0
                fi
        fi
        cd $DAEMON_PATH
        CMD="$DAEMON $DAEMONOPTS > /dev/null 2>&1"
        echo $CMD
        $CMD &
        if [ $? -eq 0 ]; then
                printf "%s\n" "Ok"
                echo $! > $PIDFILE
        else
                printf "%s\n" "Fail. Check logs $LOG_PATH"
                exit 1
        fi
        CMD1="update-rc.d sfagent defaults"
        echo $CMD1
        $CMD1 &
        if [ $? -eq 0 ]; then
                printf "\n" "symbolic link added for sfagent"
        else
                printf "%s\n" "Failed while adding symbolic link for sfagent. Check logs $LOG_PATH"
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
                killall -w td-agent-bit
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
logit "sfagent init script created"
}

print_usage()
{
    echo ""
    echo "usage of install.sh"
    echo "  ./install.sh [-h|--help][-u|--upgrade][--paths \"path1,path2\"][--env \"ENV_VAR1=value1,ENV_VAR2=value2\"]"
    echo ""
    echo "  -h|--help    show usage information"
    echo "  -u|--upgrade upgrade installed sfagent"
    echo "  --paths      comma seperated list of paths to include in PATH of sfagent service"
    echo "                 ex: \"/opt/jdk1.8.0_211/bin,/opt/jdk1.8.0_211/jre/bin\""
    echo "  --env        comma seperated list of Environemt variables"
    echo "                 ex: \"HTTP_PROXY=http://proxy.example.com,HTTPS_PROXY=https://proxy.example.com\""
    echo ""
    echo "examples:"
    echo "  ./install.sh"
    echo "  ./install.sh --install-mat"
    echo "  ./install.sh --paths \"/opt/jdk1.8.0_211/bin,/opt/jdk1.8.0_211/jre/bin\""
    echo "  ./install.sh --upgrade"
    echo "  ./install.sh --upgrade --install-mat"
    echo "  ./install.sh --upgrade --paths \"/opt/jdk1.8.0_211/bin,/opt/jdk1.8.0_211/jre/bin\""
    echo "  ./install.sh --env \"HTTP_PROXY=http://proxy.example.com,HTTPS_PROXY=https://proxy.example.com\""
    echo ""
}

UNKNOWN=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    --paths)
    INCLUDE_PATHS="$2"
    shift
    shift
    ;;
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
    --install-mat)
    INSTALL_MAT=1
    shift
    ;;
    *)
    UNKNOWN+=("$1")
    shift
    ;;
esac
done

if [ -n "$UNKNOWN" ]
then 
    logit "ERROR: unknown arguments: $UNKNOWN"
    print_usage
    exit 128
fi

if [ "$SHOW_HELP" -eq 1 ];
then
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

if [ "$INSTALL_MAT" -eq 1 ]; 
then
    install_eclipse_mat
fi    

if [ "$SHOULD_UPGRADE" -eq 1 ];
then
    ensure_system_packages
    logit "upgrading fluent-bit"
    upgrade_fluent_bit
    logit "upgrading sfagent"
    upgrade_apm_agent
    logit "upgrading sftrace agent"
    upgrade_sftrace_agent
else
    ensure_system_packages
    logit "check jcmd installed"
    check_jcmd_installation
    logit "installing fluent-bit"
    install_fluent_bit
    logit "installing sfagent"
    install_apm_agent
    logit "installing sftrace agent"
    install_sftrace_agent
fi

cd "$oldpath"
rm -rf "$tmp_dir"

sleep 1
logit "Done"
exit 0
