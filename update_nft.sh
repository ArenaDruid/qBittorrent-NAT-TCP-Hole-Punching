#!/bin/sh

#set -x

# Natter/NATMap
private_port=$4 # Natter: $3; NATMap: $4
public_port=$2 # Natter: $5; NATMap: $2

# qBittorrent.
qb_addr_url="http://localhost:8080" 
#qb_ip_addr="192.168.1.2" # Only needed when qbit runs on a different host
qb_username="admin"
qb_password="adminadmin"

# 定义一个变量，用来记录尝试次数
attempt=0
# 定义一个变量，用来存储连接状态
status=0
# 定义一个循环，最多尝试三次
while [ $attempt -lt 3 ]
do
    # 使用curl命令来检查是否能够连接到qBittorrent的地址，-s参数表示静默模式，-o参数表示输出到/dev/null，-w参数表示输出状态码
    # 如果状态码为0，表示连接成功，如果为7，表示连接失败
    status=$(curl -s -o /dev/null -w "%{http_code}" $qb_addr_url)
    # 使用if语句来判断状态码是否为7
    if [ $status -eq 7 ] then
        # 如果为7，表示连接失败，就等待一秒，然后尝试重新连接
        sleep 1
        # 尝试次数加一
        attempt=$((attempt+1))
    else
        # 如果不为7，表示连接成功，就跳出循环
        break
    fi
done

# 循环结束后，再次检查状态码是否为7
if [ $status -eq 7 ]
then
    # 如果为7，表示三次都失败了，就退出脚本并报错
    echo "Failed to connect to qBittorrent after $attempt attempts."
    exit 1
else
    echo "Update qBittorrent listen port to $public_port..."
fi

# Update qBittorrent listen port.
qb_cookie=$(curl -s -i --header "Referer: $qb_addr_url" --data "username=$qb_username&password=$qb_password" $qb_addr_url/api/v2/auth/login | grep -i set-cookie | cut -c13-48)
curl -X POST -b "$qb_cookie" -d 'json={"listen_port":"'$public_port'"}' "$qb_addr_url/api/v2/app/setPreferences"

echo "Update nftables..."

# Use nftables to forward traffic.
if nft list tables | grep -q "qbit_redirect"; then
    nft delete table inet qbit_redirect
fi
nft add table inet qbit_redirect
nft 'add chain inet qbit_redirect prerouting { type nat hook prerouting priority -100; }' 

if [ "$qb_ip_addr" = "" ];then
    nft add rule inet qbit_redirect prerouting tcp dport $private_port redirect to :$public_port
    # redirect the udp
    nft add rule inet qbit_redirect prerouting udp dport $private_port redirect to :$public_port
else
    nft add rule inet qbit_redirect prerouting tcp dport $private_port dnat to $qb_ip_addr:$public_port
    # redirect the udp
    nft add rule inet qbit_redirect prerouting udp dport $private_port dnat to $qb_ip_addr:$public_port
fi

echo "Done."