#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "[-] Please run as root (e.g., sudo bash deploy_redlight.sh)"
  exit 1
fi

echo "[+] Updating packages and installing prerequisites..."
apt-get update -y
apt-get install -y fail2ban iptables iptables-persistent

echo "[+] Configuring iptables firewall rules..."
# 1. Allow established and related connections (Prevents SSH drop)
iptables -I INPUT 1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# 2. Allow local loopback traffic
iptables -I INPUT 2 -i lo -j ACCEPT

# 3. Accept NEW connections to SSH (22) and Flag Port (8888)
iptables -I INPUT 3 -p tcp --dport 22 -j ACCEPT
iptables -I INPUT 4 -p tcp --dport 8888 -j ACCEPT

# 4. Log all other incoming SYN packets (The Portscan Trap)
iptables -I INPUT 5 -p tcp --syn -j LOG --log-prefix "CTF_PORTSCAN: "

# Save rules permanently
netfilter-persistent save

echo "[+] Writing Fail2Ban filter configuration..."
cat << 'EOF' > /etc/fail2ban/filter.d/ctf-portscan.conf
[Definition]
failregex = CTF_PORTSCAN: .* SRC=<HOST>
ignoreregex =
EOF

echo "[+] Writing Fail2Ban jail configuration..."
cat << 'EOF' > /etc/fail2ban/jail.d/ctf-portscan.conf
[ctf-portscan]
enabled  = true
filter   = ctf-portscan
backend  = systemd
maxretry = 10
findtime = 5
bantime  = 120
action   = iptables-allports[name=portscan]
EOF

echo "[+] Creating Python flag service script..."
cat << 'EOF' > /opt/redlight_flag.py
import socket

HOST = '0.0.0.0'
PORT = 8888
FLAG = b"FLAG: MARBLE{5L0W_D0wN}\n"

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind((HOST, PORT))
s.listen(5)

print(f"Listening for slow scanners on port {PORT}...")

while True:
    conn, addr = s.accept()
    try:
        conn.sendall(FLAG)
        conn.close()
    except Exception:
        pass
EOF

chmod 644 /opt/redlight_flag.py

echo "[+] Creating Systemd unit service..."
cat << 'EOF' > /etc/systemd/system/redlight-flag.service
[Unit]
Description=Red Light Green Light Flag Service
After=network.target

[Service]
Type=simple
User=nobody
ExecStart=/usr/bin/python3 /opt/redlight_flag.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

echo "[+] Reloading systemd and enabling services..."
systemctl daemon-reload
systemctl enable redlight-flag
systemctl restart redlight-flag

systemctl enable fail2ban
systemctl restart fail2ban

echo "[+] Deployment complete! Red Light Green Light challenge is active."