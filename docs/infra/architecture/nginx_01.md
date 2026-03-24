---
title: Nginx 개념과 설치 (Linux)
layout: default
parent: 아키텍처
grand_parent: 인프라
nav_order: 1
written_at: 2026-03-17
---

# Nginx 개념과 설치 (Linux)
Nginx 기초
---

## 1\. Nginx란 무엇인가?

Nginx(엔진엑스)는 **웹 서버(Web Server)** 소프트웨어로, 빠른 속도와 가벼운 구조를 가지고 있습니다.  
아파치(Apache)와 함께 전 세계적으로 가장 많이 쓰이는 웹 서버입니다.

이번 포스팅을 통해서

1) Nginx는 왜 사용해야 하는가?

2) Nginx의 기본적인 사용 방법은 어떠한가?

를 알아보려고 합니다.

## 2\. 주요 역할

-   **정적 파일 제공**: HTML, CSS, JS, 이미지 같은 정적 리소스를 빠르게 전달
-   **⭐ 리버스 프록시(Reverse Proxy)**: 클라이언트 요청을 백엔드 서버로 전달
-   **로드 밸런서(Load Balancer)**: 여러 서버로 트래픽을 분산
-   ****⭐** SSL/TLS 처리**: HTTPS 암호화 통신 지원
-   **캐싱 서버(Cache Server)**: 응답을 캐시해 속도를 높임

이러한 역할들을 수행하여 **“웹 트래픽 관리(config) 및 통로(gate)”** 역할을 한다고 볼 수 있습니다.

(모두 중요한 기능이지만 ⭐은 개인적으로 특별히 더 중요하다고 생각되는 기능)

우리가 흔히 사용하고 있는 웹 페이지들은 Nginx나 Apache가 **사용자의 요청에 따라서 교통정리**를 해주었기에 원활하게 사용할 수 있는 것입니다.

##  3. Nginx 설치

### 3-1. 설치

### Ubuntu / Debian 계열

```
sudo apt update 
sudo apt install nginx -y
```

### CentOS / RHEL 계열

```
sudo yum install epel-release -y 
sudo yum install nginx -y
```

### 3-2. 실행 및 확인

```
# Nginx 실행 
sudo systemctl start nginx 

# 부팅 시 자동 실행
sudo systemctl enable nginx 

# 상태 확인
sudo systemctl status nginx
```

이제 브라우저에서 http://서버IP 로 접속하면 **"Welcome to nginx!"** 라는 기본 페이지를 확인할 수 있습니다.

## 4\. 기본 설정 살펴보기

Nginx 설정 파일은 보통 아래 위치에서 찾을 수 있습니다.

-   /etc/nginx/nginx.conf → 메인 설정 파일
-   /etc/nginx/sites-available/ (Debian 계열)
-   /etc/nginx/conf.d/ (CentOS 계열)

이 위치에 {파일명}.conf 파일을 작성하여 아래 예시를 진행해봅시다.

### 리버스 프록시 설정 예시

아래는 Nginx를 통해 클라이언트 요청을 내부 애플리케이션 서버(예: Flask, Node.js 등)로 전달하는 간단한 설정 예시입니다.

아래 내용을 풀어서 설명해보면

> "example.com" 도메인으로 80포트(http) 접속을 시도한다면 127.0.0.1(localhost)의 5000포트로 트래픽을 전달합니다.

라는 의미의 설정 파일이 됩니다.

```
server {
    listen 80;
    server_name example.com;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

---

## 5\. 마무리

Nginx는 단순한 웹 서버를 넘어 **리버스 프록시, 로드 밸런서, SSL 게이트웨이**까지 담당할 수 있는 활용성이 넓은 도구입니다.

이를 활용하여 CORS보안, 캐시, SSL/TLS 인증서 (우리가 평소 사용하는 https 통신) 등도 세팅할 수 있습니다.