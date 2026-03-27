필요정책
대명 기본 정책

Nginx 정책 (80/443,8450)

Docker 정책

적용 방법
/etc/sysconfig/iptables 파일에 반영



# sample configuration for iptables service
# you can edit this manually or use system-config-firewall
# please do not ask us to add additional ports/services to this default configuration
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
-A INPUT -p icmp -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A INPUT -s 192.168.220.81/32 -j ACCEPT
-A INPUT -s 192.168.220.82/32 -j ACCEPT
# # 추가한 부분
# WEB
-A INPUT -p tcp -m tcp --dport 80 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 443 -j ACCEPT
# DB
# -A INPUT -p tcp -m tcp --dport 8445 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 8450 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 1213 -j DROP
-A INPUT -j REJECT --reject-with icmp-host-prohibited
-A FORWARD -j REJECT --reject-with icmp-host-prohibited
COMMIT
1. 대명 기본 정책


 -A INPUT -s 192.168.220.81/32 -j ACCEPT
 -A INPUT -s 192.168.220.82/32 -j ACCEPT
 -A INPUT -p tcp -m tcp --dport 1213 -j DROP
적용 여부 확인


sudo iptables -L INPUT -n -v --line-numbers | egrep '192\.168\.220\.81|192\.168\.220\.82|dpt:1213'
 

2. Nginx 정책
Web : 80/443



-A INPUT -p tcp -m tcp --dport 80 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 443 -j ACCEPT
DB : 8445, 8450

DB직접 접근 차단으로 인하여 프록시(stream) 정책으로 접근함.

/etc/nginx/stream.d/* 참조



-A INPUT -p tcp -m tcp --dport 8445 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 8450 -j ACCEPT
 

+@ 수동 적용 방법



sudo iptables -I INPUT 1 -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT 1 -p tcp --dport 443 -j ACCEPT
sudo iptables -I INPUT 1 -p tcp --dport 8445 -j ACCEPT
sudo iptables -I INPUT 1 -p tcp --dport 8450 -j ACCEPT
 

3. Docker 정책
docker daemon의 경우 따로 커스텀 정책이 없다면 daemon 재실행 시 host iptables 규칙 재정립 진행함.



sudo systemctl restart docker