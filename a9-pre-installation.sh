#!/bin/bash

# Elak semua popup interaktif (Ubuntu/Debian)
export DEBIAN_FRONTEND=noninteractive

# Exit immediately if a command exits with a non-zero status
set -e

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "[-] Please run this script as root or using sudo."
  exit 1
fi

NEW_PORT=20222
SSH_CONFIG="/etc/ssh/sshd_config"

# Detect Operating System
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS=$ID
else
  echo "[-] Cannot detect OS via /etc/os-release."
  exit 1
fi

echo "=========================================="
echo " Detected OS: $OS"
echo "=========================================="

# ----------------------------------------------------------------------
# 1. OS-Specific Updates and Initial Preparations
# ----------------------------------------------------------------------
case "$OS" in
ubuntu)
  echo "[+] Updating system packages (apt)..."
  apt-get update -y && apt-get upgrade -y

  echo "[+] Installing base tools..."
  apt-get install -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    bash-completion curl perl wget ca-certificates ufw

  # Disable AppArmor (cPanel compatibility)
  if systemctl is-active --quiet apparmor; then
    systemctl stop apparmor
    systemctl disable apparmor
    echo "[+] AppArmor disabled."
  fi

  # Pastikan /run/sshd wujud (fix Ubuntu privilege separation)
  echo "[+] Ensure /run/sshd exists..."
  mkdir -p /run/sshd
  chmod 0755 /run/sshd
  ;;

almalinux | rocky | rhel | centos)
  echo "[+] Updating system packages (yum/dnf)..."
  if command -v dnf &>/dev/null; then
    dnf update -y
    dnf install -y bash-completion curl perl wget policycoreutils-python-utils firewalld
  else
    yum update -y
    yum install -y bash-completion curl perl wget policycoreutils-python-utils firewalld
  fi

  echo "[+] Disabling SELinux..."
  if [ -f /etc/selinux/config ]; then
    sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
    setenforce 0 2>/dev/null || true
    echo "[+] SELinux set to disabled."
  fi
  ;;

*)
  echo "[-] Unsupported operating system: $OS"
  exit 1
  ;;
esac

echo
# ----------------------------------------------------------------------
# 2. Reconfigure SSH Port
# ----------------------------------------------------------------------
echo "=== Changing SSH port to $NEW_PORT ==="

# Backup SSH configuration
cp "$SSH_CONFIG" "${SSH_CONFIG}.bak_$(date +%F_%T)"
echo "[+] Backup created at ${SSH_CONFIG}.bak"

# Update port in sshd_config
if grep -q "^#\?Port " "$SSH_CONFIG"; then
  sed -i "s/^#\?Port .*/Port $NEW_PORT/" "$SSH_CONFIG"
else
  echo "Port $NEW_PORT" >>"$SSH_CONFIG"
fi
echo "[+] SSH Port updated to $NEW_PORT in configuration."

# SELinux Port Configuration (RHEL/AlmaLinux only)
if [ "$OS" != "ubuntu" ]; then
  if command -v semanage &>/dev/null; then
    semanage port -a -t ssh_port_t -p tcp $NEW_PORT 2>/dev/null || semanage port -m -t ssh_port_t -p tcp $NEW_PORT
    echo "[+] Port $NEW_PORT added to SELinux rules."
  fi
fi

# Firewall Configuration
if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld; then
  echo "[+] Updating firewalld rules..."
  firewall-cmd --permanent --add-port=${NEW_PORT}/tcp
  firewall-cmd --permanent --remove-service=ssh 2>/dev/null || true
  firewall-cmd --reload
  echo "[+] Current allowed ports:"
  firewall-cmd --list-ports
elif command -v ufw &>/dev/null; then
  echo "[+] Updating UFW rules..."
  ufw allow ${NEW_PORT}/tcp
  ufw --force reload
fi

# Test SSH syntax and restart service
sshd -t
if [ $? -eq 0 ]; then
  echo "[+] SSH configuration syntax is valid."
  # Auto pilih service name ikut OS
  if systemctl list-unit-files | grep -q sshd.service; then
    systemctl restart sshd.service
  else
    systemctl restart ssh.service
  fi
  echo "=== SSH Port changed to $NEW_PORT successfully ==="
else
  echo "[-] SSH syntax error detected. Restoring backup..."
  cp $(ls -t ${SSH_CONFIG}.bak_* | head -n 1) "$SSH_CONFIG"
  exit 1
fi

echo
# ----------------------------------------------------------------------
# 3. Download and Install cPanel
# ----------------------------------------------------------------------
echo "=========================================="
echo " Installing cPanel & WHM"
echo "=========================================="

read -p "Do you want to proceed with cPanel installation? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
  echo "[-] cPanel installation skipped."
else

cd /home
curl -o latest -L https://securedownloads.cpanel.net/latest
sh latest

echo
echo "=========================================="
echo " Running Force Update on cPanel"
echo "=========================================="
/usr/local/cpanel/scripts/upcp --force

echo
echo "=========================================="
echo " Setup Finished!"
echo " Log into WHM directly using:"
echo " https://$(cat /var/cpanel/mainip):2087"
echo "=========================================="
echo
echo "IMPORTANT: Please reboot your server to apply all kernel and SELinux changes."
echo "Command: sudo reboot"