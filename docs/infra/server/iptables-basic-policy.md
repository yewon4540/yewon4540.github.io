---
layout: default
title: iptables 기본 정책
parent: Server
grand_parent: 인프라
nav_order: 4
---

# iptables 기본 정책

RHEL/CentOS 계열 서버에서 `/etc/sysconfig/iptables`를 이용해 방화벽 INPUT 정책을 관리하는 방법을 정리합니다.

---

## 1. 기본 정책 구성

`*filter` 체인 기준의 기본 설정 예시입니다.

```
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
-A INPUT -p icmp -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A INPUT -s 192.168.1.10/32 -j ACCEPT
-A INPUT -s 192.168.1.20/32 -j ACCEPT
# WEB
-A INPUT -p tcp -m tcp --dport 80 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 443 -j ACCEPT
# DB (Nginx stream proxy 경유)
-A INPUT -p tcp -m tcp --dport 8450 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 1213 -j DROP
-A INPUT -j REJECT --reject-with icmp-host-prohibited
-A FORWARD -j REJECT --reject-with icmp-host-prohibited
COMMIT
```

- **신뢰 IP 대역**: 내부 관리 IP에 대해 모든 인바운드 허용
- **포트 1213**: `REJECT` 전에 명시적 `DROP` 처리
- 그 외 미허용 트래픽은 `icmp-host-prohibited`로 거부

---

## 2. 정책별 설명

### Nginx — Web (80/443)

```bash
-A INPUT -p tcp -m tcp --dport 80 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 443 -j ACCEPT
```

HTTP/HTTPS 인바운드를 허용합니다.

### Nginx — DB Stream Proxy (8445/8450)

```bash
-A INPUT -p tcp -m tcp --dport 8445 -j ACCEPT   # 필요 시 주석 해제
-A INPUT -p tcp -m tcp --dport 8450 -j ACCEPT
```

DB 직접 접근 차단 대신 Nginx stream 프록시(`/etc/nginx/stream.d/*`)를 통해 접근합니다.  
8445는 상황에 따라 주석 처리하여 운영합니다.

### 신뢰 IP 허용

```bash
-A INPUT -s 192.168.1.10/32 -j ACCEPT
-A INPUT -s 192.168.1.20/32 -j ACCEPT
```

내부 관리 IP에서의 모든 인바운드를 허용합니다.

적용 확인:

```bash
sudo iptables -L INPUT -n -v --line-numbers | egrep '192.168.1.10|192.168.1.20|dpt:1213'
```

---

## 3. 수동 적용 방법

파일 수정 없이 즉시 룰을 추가하려면:

```bash
sudo iptables -I INPUT 1 -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT 1 -p tcp --dport 443 -j ACCEPT
sudo iptables -I INPUT 1 -p tcp --dport 8445 -j ACCEPT
sudo iptables -I INPUT 1 -p tcp --dport 8450 -j ACCEPT
```

영구 반영은 `/etc/sysconfig/iptables` 파일에 직접 작성 후 서비스 재시작:

```bash
sudo systemctl restart iptables
```

---

## 4. Docker 주의사항

Docker daemon은 자체적으로 iptables 규칙을 관리합니다.  
커스텀 정책이 없는 경우, daemon 재시작 시 host iptables 규칙이 **재정립**됩니다.

```bash
sudo systemctl restart docker
```

Docker와 iptables 정책 충돌이 발생하는 경우, `DOCKER-USER` 체인에 규칙을 추가하는 방식을 권장합니다.
