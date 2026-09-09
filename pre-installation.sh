echo install bash-completion
yum install bash-completion -y
echo
echo

echo disabled selinux. restart required
sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config && sudo setenforce 0
echo
echo
