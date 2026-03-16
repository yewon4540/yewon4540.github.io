---
title: Nexus Repository 기본 개념 & 설치 가이드
layout: default
parent: Nexus
grand_parent: Devops
nav_order: 1
---

# Nexus Repository 기본 개념 & 설치 가이드

> docker hub있는데 왜 Nexus 씀? 에 대해서 얘기해볼까 합니다

---

## 목차

1. [Nexus Repository란 무엇인가?](#1-nexus-repository란-무엇인가)
2. [선행 개념 : 아티팩트 저장소란?](#2-선행-개념--아티팩트-저장소artifact-repository란)
3. [Docker를 통해 Nexus 설치하기](#3-docker를-통해-nexus-설치하기)
4. [로컬 vs 서버(운영) 설치 차이](#4-로컬-vs-서버운영-설치-차이)
5. [보안 설정 체크리스트](#5-보안-설정-체크리스트)

---

## 1) Nexus Repository란 무엇인가?

**개요** : Nexus는 Docker Image 등의 빌드 결과물을 저장하는 장소입니다.

유사한 서비스로는 Docker hub, Maven Central 등이 있습니다.

도커에 익숙하신 분들이라면 꽤나 자주 써봤을 명령어

```
Docker pull ${Image_Name}
```

위 명령어는 Docker hub라는 저장소에서 이미지를 가져옵니다.

풀어서 써보면

```
docker pull docker.io/library/${Image_Name}
```

위와 같은 경로가 생략되어 있는거죠.  
이러한 dockerhub(docker.io)가 아닌, 다른 종류의 저장소인 nexus에 대해서 서술해볼까 합니다.

## 2) 선행 개념 : 아티팩트 저장소(Artifact Repository)란?

-   **Artifact(아티팩트)란?**: 빌드 결과물(JAR/WAR, npm 패키지, Python wheel, Docker Image 등)
-   **왜 중앙 저장소를 사용할까요?**
    1.  **재사용/공유**: 한 번 만든 걸 여러 서비스가 안전하게 재사용
    2.  **속도/안정성**: 외부 레지스트리 장애와 네트워크 지연을 줄임
    3.  **보안/품질**: 검증된 산출물만 쓰도록 검증하여 업로드하는 역할

Nexus의 3대 저장소 타입:

-   **Proxy**: 외부 저장소를 **캐싱**해 팀 내부에 빠르게 공급 (예: Maven Central 프록시, 스토리지 등)
-   **Hosted**: 우리 팀이 만든 산출물을 **직접 보관**
-   **Group**: 여러 저장소를 **하나의 엔드포인트로 묶기** (개발자 입장에선 URL 하나)

즉, 아티팩트 버전 관리 / 저장 / 공유 를 하기 위한 '프라이빗 보관소' 라고 보시면 되겠습니다.

---

## 3) Docker를 통해 Nexus 설치하기

### 3-1) 준비물

-   Docker, Docker Compose 설치

더보기

우분투 Docker 설치 스크립트

```
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update -y 
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker ${USER}
```

-   권장 스펙: **2 vCPU / 4–8GB RAM / 디스크 여유** (추후 들어갈 아키택트 용량 고려)

### 3-2) docker-compose.yml

```
services:
  nexus:
    image: sonatype/nexus3:latest # nexus3 이미지 최신 버전
    container_name: nexus # 컨테이너 이름
    ports: # 포트 지정
      - "5000:5000"   # Nexus docker 기본 포트
      - "8081:8081"   # Nexus UI
    volumes: # 볼륨 지정
      - ./nexus-data:/nexus-data
```

> **❗️** **권한 이슈 발생 시(리눅스)**: 필요 시 sudo chown -R 200:200 nexus-data (Nexus 컨테이너의 런타임 UID/GID가 200)

```
docker compose up -d
```

```
http://${host}:8081

# 내 PC(로컬)이라면
http://localhost:8081
```

초기 관리자 비밀번호:

```
cat ./nexus-data/admin.password
```

---

## 4) 로컬 vs 서버(운영) 설치 차이

**로컬(개발용)**

-   개인 실습/테스트용, 포트 그대로 노출(8081)
-   백업은 필요 최소한으로

**서버(팀 공유/운영)**

-   **도메인 + HTTPS** 적용 권장
-   정기 **백업 + 모니터링**(디스크/메모리, repo 용량)
-   사내 인증(SSO/LDAP)과 **권한 Role** 설계

Nginx 리버스 프록시 예시:

```
server {
  listen 80;
  server_name nexus.example.com;
  return 301 https://$host$request_uri;
}

server {
  listen 443 ssl;
  server_name nexus.example.com;

  ssl_certificate     /etc/letsencrypt/live/nexus.example.com/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/nexus.example.com/privkey.pem;

  client_max_body_size 4g; # 최대 용량 제한 (권장) / 0으로 설정 시 제한없음
  
  # 타임아웃 설정 (권장)
  proxy_read_timeout  900s;
  proxy_send_timeout  900s;
  send_timeout        900s;
  
  location / {
    # 대용량 첨부 / 장시간 세션 유지 필요 시 설정 (권장)
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_request_buffering off
    
    # 필수 섹션
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-Proto https;
    proxy_pass http://nexus:8081;
  }
}
```

\- Docker registry 예시

더보기

```
server {
  listen 443 ssl http2;
  server_name registry.example.com;

  ssl_certificate     /etc/letsencrypt/live/registry.example.com/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/registry.example.com/privkey.pem;

  client_max_body_size 0;  # 레지스트리는 제한 없음 권장(아니면 충분히 크게)

  location /v2/ {
    proxy_pass http://nexus:5000;     # ← Nexus Docker repo의 HTTP 포트(예: 5000)
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $remote_addr;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    proxy_read_timeout 3600s;
    proxy_request_buffering off;       # 큰 레이어 업로드 스트리밍
    # chunked_transfer_encoding on;    # HTTP/1.1이면 기본 활성(명시해도 무방)
  }
}
```

> 컨테이너 네트워크(예: docker network create proxy), Nginx와 Nexus를 같은 네트워크에 연결하여 proxy\_pass http://nexus:8081;처럼 서비스명으로 라우팅하는 구성이 편합니다.

---

## 5) 보안 설정 체크리스트

1.  **admin** **비밀번호 즉시 변경**
2.  **Anonymous(익명) 권한 최소화** 또는 비활성화
3.  필요한 **리포지토리 타입만 활성화**해 표면적 줄이기
4.  **Cleanup 정책**(Snapshot 보관 기간)으로 디스크 관리
5.  Docker 레지스트리 사용 시 **“Docker Bearer Token Realm”** 활성화

---