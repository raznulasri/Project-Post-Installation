echo patching update
yum update -y
echo
echo


echo install bash-completion
yum install bash-completion -y
echo
echo

echo disabled selinux. restart required
sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config && sudo setenforce 0
echo
echo

echo change port to standard policy
#!/bin/bash

# Pastikan skrip dijalankan sebagai root
if [ "$EUID" -ne 0 ]; then
  echo "Sila jalankan skrip ini sebagai root atau guna sudo."
  exit 1
fi

NEW_PORT=20222
SSH_CONFIG="/etc/ssh/sshd_config"

echo "=== Mula menukar port SSH kepada $NEW_PORT (AlmaLinux) ==="

# 1. Sandarkan (backup) fail konfigurasi asal
cp $SSH_CONFIG "${SSH_CONFIG}.bak_$(date +%F_%T)"
echo "[+] Salinan sandaran dicipta di $SSH_CONFIG"

# 2. Kemaskini Port dalam sshd_config
if grep -q "^#\?Port " $SSH_CONFIG; then
  sed -i "s/^#\?Port .*/Port $NEW_PORT/" $SSH_CONFIG
else
  echo "Port $NEW_PORT" >>$SSH_CONFIG
fi
echo "[+] Port SSH ditukar kepada $NEW_PORT dalam $SSH_CONFIG."

# 3. Khas untuk AlmaLinux: Benarkan port pada SELinux
if command -v semanage &>/dev/null; then
  semanage port -a -t ssh_port_t -p tcp $NEW_PORT 2>/dev/null || semanage port -m -t ssh_port_t -p tcp $NEW_PORT
  echo "[+] Port $NEW_PORT dibenarkan pada SELinux."
else
  echo "[!] Pakej policycoreutils-python-utils dipasang untuk kemaskini SELinux..."
  dnf install -y policycoreutils-python-utils
  semanage port -a -t ssh_port_t -p tcp $NEW_PORT
  echo "[+] Port $NEW_PORT dibenarkan pada SELinux."
fi

# 4. Khas untuk AlmaLinux: Benarkan port pada firewalld
if systemctl is-active --quiet firewalld; then
  firewall-cmd --permanent --add-port=${NEW_PORT}/tcp
  firewall-cmd --reload
  echo "[+] Port $NEW_PORT dibenarkan pada firewalld."
fi

# 5. Semak ketepatan sintaks SSH & mulakan semula perkhidmatan
sshd -t
if [ $? -eq 0 ]; then
  echo "[+] Sintaks konfigurasi SSH sah."
  systemctl restart sshd
  echo "=== SIAP! Port SSH AlmaLinux telah ditukar kepada $NEW_PORT ==="
  echo "Uji sambungan baharu pada terminal berasingan:"
  echo "ssh -p $NEW_PORT pengguna@ip_almalinux"
else
  echo "[-] Terdapat ralat sintaks. Memulihkan konfigurasi asal..."
  cp $(ls -t ${SSH_CONFIG}.bak_* | head -n 1) $SSH_CONFIG
fi

echo
echo

firewall-cmd --permanent --add-port=20222/tcp
firewall-cmd --permanent --remove-service=ssh
firewall-cmd --reload
firewall-cmd --list-ports

echo
echo "Please reboot your server"
echo