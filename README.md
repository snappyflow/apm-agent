# Platforms tested
- ubuntu 18 lts
- ubuntu 16 lts
- centos 7

## Usage
```
usage of install.sh
./install.sh [-h|--help][-u|--upgrade][][-p|--include-paths "/opt/jdk1.8.0_211/bin,/opt/jdk1.8.0_211/jre/bin"]
  -h|--help          show usage information
  -u|--upgrade       upgrade installed sfagent
  -p|--include-paths comma seperated list of paths to include in PATH of sfagent service
```
## Install commands (run as root user with sudo privileges)
```
Download script using Wget:
wget https://raw.githubusercontent.com/snappyflow/apm-agent/master/install.sh

Download script using curl
curl -fsSL -o install.sh https://raw.githubusercontent.com/snappyflow/apm-agent/master/install.sh

chmod +x install.sh
sudo ./install.sh

Yes, you can also run
curl -s https://raw.githubusercontent.com/snappyflow/apm-agent/master/install.sh | bash
```

## Upgrade commands (run as root user with sudo privileges)
```
sudo ./install.sh -u
or
sudo ./install.sh --upgrade
```

## Include additional paths in PATH variable during install/upgrade
- useful if java is not installed on the system PATH's
```
sudo ./install.sh -p "/opt/jdk1.8.0_211/bin,/opt/jdk1.8.0_211/jre/bin"
```


## apm-agent uninstaller

1) download uninstall.sh
2) execute **chmod +x uninstall.sh** to give executable permision
3) run uninstall.sh as root to uninstall td-agent-bit and sfagent

## using ansible playbook
1) make sure targets nodes have python installed on them.
2) ansible playbook uses install.sh internally
3) install ansible using **pip install -r requirements.txt**
4) update hosts file, sample can be found in hosts.sample
5) To Install: execute command **ansible-playbook -vv -b -i hosts --key-file=ssh-key.pem playbook.yaml**
6) To Upgrade: execute command **ansible-playbook -vv -b -i hosts --key-file=ssh-key.pem upgrade-playbook.yaml**
