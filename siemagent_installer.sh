#!/bin/bash

WMANAGER_IP=0.0.0.0
CONFIG_FILE=/var/ossec/etc/ossec.conf

logit() 
{
    echo "[$(date +%d/%m/%Y-%T)] - ${*}"
}

add_labels()
{
    cat << EOF >> ${CONFIG_FILE}
<ossec_config>
  <labels>
    <label key="projectName">${TAGPROJECTNAME}</label>
    <label key="appName">${TAGAPPNAME}</label>
    <label key="Name">${TAGNAME}</label>
  </labels>
</ossec_config>
EOF
}

update_labels()
{
    sed -i "s/.*<label key=\"projectName\".*/    <label key=\"projectName\">${TAGPROJECTNAME}<\/label>/" ${CONFIG_FILE}
    sed -i "s/.*<label key=\"appName\".*/    <label key=\"appName\">${TAGAPPNAME}<\/label>/" ${CONFIG_FILE}
    sed -i "s/.*label key=\"Name\".*/    <label key=\"Name\">${TAGNAME}<\/label>/" ${CONFIG_FILE}
}

update_ip()
{
    sed -i "s/.*<address>.*/      <address>${WMANAGER_IP}<\/address>/" ${CONFIG_FILE}
}

restart_service()
{
    systemctl restart wazuh-agent
    logit "Restarted SIEM Agent service."
}

uninstall_agent()
{
    check_distribution
    if [ "$ubuntu" = true ]; then
        apt-get remove wazuh-agent -y
    elif [ "$centos" = true ]; then
        yum remove wazuh-agent -y
    fi
    systemctl daemon-reload
    logit "SIEM Agent is removed from system."
}

upgrade_agent()
{
    check_distribution
    if [ "$ubuntu" = true ]; then
        ubuntu_upgrade
    elif [ "$centos" = true ]; then
        centos_upgrade
    fi
    logit "SIEM Agent is upgraded successfully."
}

ubuntu_upgrade()
{
    curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import && chmod 644 /usr/share/keyrings/wazuh.gpg
    echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" | tee -a /etc/apt/sources.list.d/wazuh.list
    apt-get update
    apt-get install wazuh-agent
    sed -i "s/^deb/#deb/" /etc/apt/sources.list.d/wazuh.list
    apt-get update
}

centos_upgrade()
{
    rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH
    cat > /etc/yum.repos.d/wazuh.repo << EOF
[wazuh]
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
name=EL-\$releasever - Wazuh
baseurl=https://packages.wazuh.com/4.x/yum/
protect=1
EOF
    sed -i "s/^enabled=1/enabled=0/" /etc/yum.repos.d/wazuh.repo
    yum clean all
    yum upgrade wazuh-agent
}

ubuntu_installation()
{
    curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import && chmod 644 /usr/share/keyrings/wazuh.gpg
    echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" | tee -a /etc/apt/sources.list.d/wazuh.list
    apt-get update
    apt-get -y install wazuh-agent
    update_ip
    add_labels
    sed -i "s/^deb/#deb/" /etc/apt/sources.list.d/wazuh.list
    apt-get update
    systemctl daemon-reload
    systemctl enable wazuh-agent
    systemctl start wazuh-agent
}

centos_installation()
{
    rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH
    cat > /etc/yum.repos.d/wazuh.repo << EOF
[wazuh]
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
name=EL-\$releasever - Wazuh
baseurl=https://packages.wazuh.com/4.x/yum/
protect=1
EOF
    WAZUH_MANAGER="$WMANAGER_IP" yum -y install wazuh-agent
    add_labels
    sed -i "s/^enabled=1/enabled=0/" /etc/yum.repos.d/wazuh.repo
    systemctl daemon-reload
    systemctl enable wazuh-agent
    systemctl start wazuh-agent
}

#OS support to be added in this block
check_distribution()
{
    distro_name=$(awk -F '=' '/PRETTY_NAME/ { print $2 }' /etc/os-release)
    echo $distro_name
    if [[ "$distro_name" == *"Ubuntu"* ]]; then
        ubuntu=true
    elif [[ "$distro_name" == *"CentOS"* ]] || [[ "$distro_name" == *"Amazon Linux"* ]]; then
        centos=true
    fi
}

case "$1" in
install)
    if [ -z "$2" ]
        then
            read -p "Continue installation without SIEM Appliance IP (y/n)? " choice
            case "$choice" in 
                y|Y ) echo "";;
                n|N ) echo "Exiting installation!" && exit 1;;
                * ) echo "invalid response" && exit 1;;
            esac
    else
        WMANAGER_IP=$2
    fi
    TAGPROJECTNAME=${3:-"CHANGEME"}
    TAGAPPNAME=${4:-"CHANGEME"}
    TAGNAME=${5:-"CHANGEME"}
    echo "####-----------------------####"
    echo "SIEM Appliance IP -> " $WMANAGER_IP
    echo "Tag projectName -> " $TAGPROJECTNAME
    echo "Tag appName -> " $TAGAPPNAME
    echo "Tag Name -> " $TAGNAME
    echo "####-----------------------####"
    printf "Usage: $0 install <ip> <projectName> <appName> <Name>\n\n"
    read -p "Continue installation with the following parameters (y/n)? " choice
        case "$choice" in 
            y|Y ) echo "";;
            n|N ) echo "Exiting installation!" && exit 1;;
            * ) echo "invalid response" && exit 1;;
        esac
    logit "Starting installation of SIEM Agent..."
    check_distribution
    if [ "$ubuntu" = true ]; then
        ubuntu_installation
    elif [ "$centos" = true ]; then
        centos_installation
    fi
    ;;
update_ip)
    if [ -z "$2" ]
        then
            printf "Usage: $0 update_ip 0.0.0.0\n"
            exit 1
    else
        WMANAGER_IP=$2
        update_ip
        restart_service
        printf "\nUpdated SIEM Appliance IP in config file: ${CONFIG_FILE}\n"
    fi
    ;;
update_tags)
    TAGPROJECTNAME=${2:-"CHANGEME"}
    TAGAPPNAME=${3:-"CHANGEME"}
    TAGNAME=${4:-"CHANGEME"}
    echo "####-----------------------####"
    echo "Tag projectName -> " $TAGPROJECTNAME
    echo "Tag appName -> " $TAGAPPNAME
    echo "Tag Name -> " $TAGNAME
    echo "####-----------------------####"
    printf "Usage: $0 update_tags <projectName> <appName> <Name>\n\n"
    read -p "Continue to update the following tags (y/n)? " choice
        case "$choice" in 
            y|Y ) echo "";;
            n|N ) echo "Exiting installation!" && exit 1;;
            * ) echo "invalid response" && exit 1;;
        esac
    update_labels
    restart_service
    logit "Updated Labels in config file : ${CONFIG_FILE}\n"
    ;;
stop)
    systemctl stop wazuh-agent
    logit "Stopped SIEM agent service."
    ;;
start)
    systemctl start wazuh-agent
    logit "Started SIEM agent service."
    ;;
restart)
    systemctl restart wazuh-agent
    logit "Restarting SIEM agent service."
    ;;
status)
    logit "Fetching status of SIEM agent service."
    systemctl status wazuh-agent
    ;;
view)
    cat $CONFIG_FILE
    ;;
upgrade)
    logit "Upgrading SIEM Agent"
    upgrade_agent
    ;;
uninstall)
    read -p "Remove SIEM agent (y/n)? " choice
        case "$choice" in 
            y|Y ) logit "Uninstalling SIEM agent ..." && uninstall_agent;;
            n|N ) echo "Exit." && exit 1;;
            * ) echo "invalid response" && exit 1;;
        esac
    ;;
--help)
    echo "SIEM Agent Installer User Guide"
    echo ""
    cat << EOF
Usage : $0 [OPTIONS]

Options:

install <ip> <projectName> <appName> <Name>         -> installs siem agent
update_ip <ip>                                      -> to update ip in config file
update_tags <projectName> <appName> <Name>          -> to update labels in config file
stop                                                -> to stop the service temporarily
start                                               -> start service
status                                              -> check status of service
view                                                -> view the config file
restart                                             -> to restart the service
upgrade                                             -> upgrade SIEM agent(Note: Take back up of config file before upgrading)
uninstall                                           -> Remove siem agent from system

EOF
    ;;
*)
   printf "\nUsage: $0 {install|update_ip|update_tags|stop|start|restart|status|view|upgrade|uninstall}\n"
   echo "use --help to view SIEM Agent Installer User Guide"
   ;;
esac

exit 0