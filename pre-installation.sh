echo install bash-completion
yum install bash-completion -y

echo disabled selinux. restart required
sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config && sudo setenforce 0
