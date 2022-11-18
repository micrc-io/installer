
#!/bin/bash


echo "#######################################"
echo "## Start -- 开始准备环境"
echo "#######################################"


echo "==========关闭防火墙和selinux=========="
systemctl stop firewalld && systemctl disable firewalld
setenforce 0
sed -i '7s/enforcing/disabled/' /etc/selinux/config
echo "================Done.=================="


# 关闭swap分区
echo "===========关闭swap分区================"
swapoff -a
sed -i '/^\/dev\/mapper\/centos-swap/c#/dev/mapper/centos-swap swap                    swap    defaults        0 0' /etc/fstab
cat /etc/fstab
free -m

echo 'vm.swappiness = 0' >> /etc/sysctl.d/k8s.conf
sysctl -p /etc/sysctl.d/k8s.conf
echo "=============Done.====================="


echo "===============更新nexus yum仓库==================="
mkdir -p /etc/yum.repos.d/bak
mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/bak

tee /etc/yum.repos.d/nexus.repo <<-'EOF'
[base]
name=CentOS-$releasever - Base
baseurl=http://10.0.1.100:8088/repository/yum-group/$releasever/os/$basearch/
gpgcheck=0

[updates]
name=CentOS-$releasever - Updates
baseurl=http://10.0.1.100:8088/repository/yum-group/$releasever/updates/$basearch/
gpgcheck=0

[extras]
name=CentOS-$releasever - Extras
baseurl=http://10.0.1.100:8088/repository/yum-group/$releasever/extras/$basearch/
gpgcheck=0

[epel]
name=CentOS-$releasever - epel
baseurl=http://10.0.1.100:8088/repository/yum-group/$releasever/$basearch/
gpgcheck=0

[docker-ce]
name=Docker CE Stable - $basearch
baseurl=http://10.0.1.100:8088/repository/yum-group/$releasever/$basearch/stable
gpgcheck=0
EOF
#更新源
yum update -y
mkdir -p /etc/yum.repos.d/bak
mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/bak

tee /etc/yum.repos.d/nexus.repo <<-'EOF'
[base]
name=CentOS-$releasever - Base
baseurl=http://10.0.1.100:8088/repository/yum-group/$releasever/os/$basearch/
gpgcheck=0

[updates]
name=CentOS-$releasever - Updates
baseurl=http://10.0.1.100:8088/repository/yum-group/$releasever/updates/$basearch/
gpgcheck=0

[extras]
name=CentOS-$releasever - Extras
baseurl=http://10.0.1.100:8088/repository/yum-group/$releasever/extras/$basearch/
gpgcheck=0

[epel]
name=CentOS-$releasever - epel
baseurl=http://10.0.1.100:8088/repository/yum-group/$releasever/$basearch/
gpgcheck=0

[docker-ce]
name=Docker CE Stable - $basearch
baseurl=http://10.0.1.100:8088/repository/yum-group/$releasever/$basearch/stable
gpgcheck=0
EOF
yum repolist
echo "=======================Done.===================="


echo "===============同步时间=================="
yum -y install chrony
sed -i.bak '3,6d' /etc/chrony.conf && sed -i '3cserver ntp1.aliyun.com iburst' /etc/chrony.conf
systemctl start chronyd && systemctl enable chronyd

chronyc sources
timedatectl set-timezone Asia/Shanghai
date
echo "================Done.===================="


echo "==========加载br_netfilter模块========="
touch /etc/sysctl.d/k8s.conf
tee /etc/sysctl.d/k8s.conf <<-'EOF'
net.bridge.bridge-nf-call-ip6tables = 1 > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1 >> /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1 >> /etc/sysctl.d/k8s.conf
EOF
modprobe br_netfilter && sysctl -p /etc/sysctl.d/k8s.conf
sysctl --system
echo "================Done.=================="


echo "=========安装ipvs, ipset和ipvsadm======"
touch /etc/sysconfig/modules/ipvs.modules
tee /etc/sysconfig/modules/ipvs.modules <<-'EOF'
#!/bin/bash
modprobe -- ip_vs
modprobe -- ip_vs_rr
modprobe -- ip_vs_wrr
modprobe -- ip_vs_sh
modprobe -- nf_conntrack_ipv4
EOF
chmod 755 /etc/sysconfig/modules/ipvs.modules
bash /etc/sysconfig/modules/ipvs.modules && lsmod | grep -e ip_vs -e nf_conntrack_ipv4
yum -y install ipset ipvsadm
echo "===============Done.==================="


echo "===========安装docker-ce============="
yum -y install docker-ce docker-ce-cli

mkdir ~/.docker
touch ~/.docker/config.json
tee ~/.docker/config.json <<-'EOF'
{
 "proxies":
 {
   "default":
   {
     "httpProxy": "http://10.0.1.100:7890",
     "httpsProxy": "http://10.0.1.100:7890",
     "noProxy": "127.0.0.0/8,localhost,100.233.64.0/18,100.233.0.0/18,10.0.0.0/16"
   }
 }
}
EOF

systemctl enable docker && systemctl start docker

touch /etc/docker/daemon.json
tee /etc/docker/daemon.json <<-'EOF'
{
  "log-opts": {
    "max-size": "5m",
    "max-file": "3"
  },
  "registry-mirrors": ["http://10.0.1.100:5748"],
  "insecure-registries": ["10.0.1.100:5748"],
  "exec-opts": ["native.cgroupdriver=systemd"]
}
EOF

systemctl daemon-reload
systemctl restart docker

docker info
docker version
echo "===============Done.=================="



echo "===安装iSCSI client -- for openebs==="
yum install iscsi-initiator-utils -y
systemctl start iscsid
systemctl enable iscsid
echo "============Done.===================="


echo "======================安装依赖===================="
yum install socat nfs-utils rpcbind wget jq psmisc vim yum-utils net-tools telnet openssl ebtables ipset conntrack device-mapper-persistent-data lvm2  ntpdate ipvsadm ipset sysstat conntrack libseccomp -y
echo "======================Done.======================"


echo "######################################"
echo "## Successful -- 环境准备完成."
echo "######################################"

# 重启
echo "==============重启===================="
sync;reboot



