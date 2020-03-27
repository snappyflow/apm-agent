## Platforms tested
- ubuntu 18 lts
- ubuntu 16 lts
- centos 7

## Install commands (run as root user with sudo privileges)
1) wget https://github.com/snappyflow/apm-agent/blob/master/install.sh
2) chmod +x install.sh
3) sudo ./install.sh

## Upgrade commands (run as root user with sudo privileges)
1) sudo ./install.sh upgrade

## apm-agent installer

1) download install.sh
2) execute **chmod +x install.sh** to give executable permision
3) run install.sh as root to install td-agent-bit and sfagent
4) run **sh install.sh upgrade** to upgrade binaries

## using ansible playbook
1) make sure targets nodes have python installed on them.
2) ansible playbook uses install.sh internally
3) install ansible using **pip install -r requirements.txt**
4) update hosts file, sample can be found in hosts.sample
5) execute command **ansible-playbook -vv -b -i hosts --key-file=ssh-key.pem playbook.yaml**
