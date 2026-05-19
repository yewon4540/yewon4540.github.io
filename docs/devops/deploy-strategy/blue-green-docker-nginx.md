---
title: Docker Compose + Nginx reverse proxy로 만든 가장 단순한 Blue-Green 배포 구조
layout: default
parent: 배포 전략
grand_parent: Devops
nav_order: 1
written_at: 2026-05-19
---

# Docker Compose + Nginx reverse proxy로 만든 가장 단순한 Blue-Green 배포 구조

배포 자동화를 익히기 위해 작은 Flask 웹 애플리케이션 하나를 골라
**Blue-Green 배포 흐름을 직접 손으로 짜본 적**이 있습니다.

기능 자체보다 "어떻게 배포할 것인가"에 집중한 토이 프로젝트인데,
이 구조 자체가 Blue-Green의 핵심을 단순하게 보여주는 형태라서 정리해보려고 합니다.

이번 글에서는 다음에 집중합니다.

- 왜 Blue-Green을 골랐는가
- 컨테이너 / Nginx / Docker Compose가 어떻게 묶여 있는가
- 트래픽이 한 색상에서 다른 색상으로 어떻게 넘어가는가

배포 스크립트(`deploy.sh`)와 Jenkins 자동화 부분은 분량이 충분히 별도라
다음 글로 분리해서 정리합니다.

---

## 1. 발단

토이 프로젝트를 여러 개 만들기보다,
"작은 서비스 하나라도 배포 자동화 흐름을 구조적으로 보여주는 프로젝트"가 더 의미 있다고 느꼈습니다.

그래서 다음과 같이 목표를 잡았습니다.

- Flask 앱을 컨테이너로 실행
- Nginx를 reverse proxy로 두고 트래픽 라우팅 제어
- 신규 컨테이너를 띄우는 동안 기존 컨테이너는 계속 서비스 유지
- 헬스체크 통과 후 트래픽을 신규 쪽으로 전환
- 이전 컨테이너는 트래픽 전환 후 종료

이 흐름을 구현하면서 자연스럽게 Blue-Green 배포의 모양이 잡혔습니다.

---

## 2. 왜 Blue-Green인가

처음에는 단순히 `docker compose up`으로 한 컨테이너를 재배포하는 방식부터 떠올렸습니다.
그런데 그 방식에는 다음 한계가 있었습니다.

- 기존 컨테이너가 내려가는 짧은 시간 동안 503이 발생
- 신규 컨테이너가 시작 직후 곧바로 트래픽을 받게 됨 → 워밍업 부족
- 문제가 생겼을 때 즉시 롤백할 수 있는 안전망이 없음

Blue-Green 방식은 이 세 가지 한계를 가장 단순한 형태로 해결합니다.

- 기존 컨테이너(예: blue)는 트래픽을 그대로 받고 있는 채로
- 신규 컨테이너(green)를 먼저 띄우고
- 헬스체크가 통과되면 Nginx의 `proxy_pass` 대상을 green으로 바꾸고
- 그 시점 이후로 기존(blue)을 종료

즉, **사용자 진입점(Nginx)은 그대로 두고, 내부 서비스 컨테이너만 교체**하는 방식입니다.

이렇게 보면 Blue-Green이라는 이름은 색상 두 개를 번갈아 가리킨다는 의미일 뿐이고,
실제 본질은 "트래픽 수신 지점을 고정하고, 그 뒤의 컨테이너를 교체 가능한 자원으로 다룬다"는 점에 가깝습니다.

---

## 3. 구조

전체 구조는 3개의 컨테이너로 단순하게 잡았습니다.

```text
[사용자]
   ↓
[Nginx (web_server)]   ← 외부 진입점, 고정
   ↓ proxy_pass
[draw_blue]  또는  [draw_green]   ← 둘 중 하나만 활성
```

각 컨테이너 역할은 다음과 같습니다.

| 컨테이너 | 역할 |
| --- | --- |
| `web_server` | Nginx reverse proxy. 외부 80 포트 진입을 받아 내부 컨테이너로 전달 |
| `draw_blue` | Flask 앱 컨테이너. 현재 활성 또는 다음 배포 대상 중 하나 |
| `draw_green` | Flask 앱 컨테이너. 위와 같은 역할의 반대 색상 |

세 컨테이너 모두 같은 Docker 네트워크(`draw_network`)에 묶어두면
Nginx가 컨테이너 이름으로 내부 통신할 수 있습니다.

---

## 4. Compose 파일 분리

토이 프로젝트지만, **Blue/Green 컨테이너를 서로 다른 Compose 파일로 분리**한 게 핵심입니다.

```text
random-draw-bluegreen-deploy/
├── blue.yml     # Blue 앱 컨테이너만 정의
├── green.yml    # Green 앱 컨테이너만 정의
├── nginx.yml    # Nginx 컨테이너 정의
├── deploy.sh    # 배포 스크립트
└── nginx.conf/  # Nginx 설정
```

이렇게 분리해 두면 다음과 같이 한 색상씩 띄우고 내릴 수 있습니다.

```bash
docker compose -f blue.yml  up -d --build
docker compose -f blue.yml  down
docker compose -f green.yml up -d --build
```

같은 `docker-compose.yml` 안에서 두 서비스를 정의해도 동작은 하지만,
파일을 나눠두면 **활성 색상과 대기 색상을 명확히 분리해서 다룰 수 있다는 장점**이 있습니다.
스크립트에서 "현재 어느 파일을 띄워둔 상태인가"를 단순히 컨테이너 이름으로 판단할 수 있게 됩니다.

---

## 5. Nginx reverse proxy 구성

Nginx 설정은 단순합니다.
`default.conf`에서 `proxy_pass` 대상으로 현재 활성 컨테이너 이름을 잡아주면 끝입니다.

```nginx
server {
    listen 80;

    location /health {
        return 200 'ok';
    }

    location / {
        proxy_pass         http://draw_blue:5179;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
    }
}
```

배포 시 이 파일의 `proxy_pass http://draw_blue:5179` 부분을
`proxy_pass http://draw_green:5179`로 교체하는 게 트래픽 전환의 핵심입니다.

교체 후 Nginx만 재시작하면 됩니다.

```bash
docker exec web_server nginx -s reload
```

`reload`는 기존 연결을 유지한 채 새 설정을 적용하기 때문에,
이 시점에 들어오는 신규 요청부터 자연스럽게 새 컨테이너로 전달됩니다.

> `nginx -s reload`는 graceful 한 동작이라 진행 중인 요청은 끊기지 않습니다.
> 컨테이너를 통째로 재기동하는 것과는 의미가 다릅니다.

---

## 6. 배포 흐름 한눈에 보기

이제 위 구조 위에서 실제 Blue-Green 흐름이 어떻게 떨어지는지 정리해 보면 이렇습니다.

```text
1. 현재 활성 색상 확인
   → draw_blue가 떠 있다면 다음 색상은 green

2. 반대 색상 컨테이너 실행
   → docker compose -f green.yml up -d --build

3. 신규 컨테이너 헬스체크
   → curl http://draw_green:5179/health 가 200 떨어질 때까지 대기

4. Nginx 설정 교체
   → default.conf의 proxy_pass를 draw_green:5179 로 변경

5. Nginx reload
   → docker exec web_server nginx -s reload

6. 이전 컨테이너 종료
   → docker compose -f blue.yml down
```

이 6단계가 Blue-Green 배포의 가장 단순한 형태입니다.

이 중 4번이 진짜 트래픽 전환 시점이고,
그 직전까지는 기존 컨테이너가 정상적으로 서비스를 유지하고 있습니다.

만약 3번의 헬스체크가 실패하면, 4번 이후로 진행하지 않고 그 자리에 멈추면 됩니다.
사용자 트래픽은 여전히 기존 컨테이너가 받고 있으니, 운영 측면에서는 사실상 무중단입니다.

---

## 7. 짚어두고 싶은 것들

### 7-1. Blue-Green의 본질은 "트래픽 수신 지점 고정"

처음에는 "컨테이너를 두 개 띄워서 번갈아 쓰는 거"라고만 봤는데,
직접 짜보고 나니 핵심은 다른 데 있었습니다.

> Nginx 같은 진입점을 하나 두고,
> 그 뒤의 워크로드를 교체 가능한 자원으로 다루는 것.

이 시각에서 보면 K8s Service + 두 Deployment 도 Blue-Green이고,
ALB target group 교체도 Blue-Green입니다.
도구만 바뀌고 본질은 같습니다.

### 7-2. Compose 파일을 색상별로 나눠두면 스크립트가 단순해진다

`blue.yml` / `green.yml` 로 나눠두면, 배포 스크립트가 다음 한 줄로 끝납니다.

```bash
docker compose -f ${NEXT_COLOR}.yml up -d --build
```

활성 색상 판단도 단순하게 컨테이너 이름 기반으로 가능합니다.

```bash
if docker ps --format '{{.Names}}' | grep -q draw_blue; then
  CURRENT=blue
else
  CURRENT=green
fi
```

같은 docker-compose.yml 안에서 두 서비스를 정의했다면 이런 단순함이 안 나옵니다.

### 7-3. `nginx -s reload`는 graceful 하다

이 명령은 다음 동작을 합니다.

- 마스터 프로세스가 새 설정을 읽음
- 워커 프로세스를 새 설정으로 새로 띄움
- 기존 워커는 진행 중인 요청을 끝까지 처리한 뒤 종료

즉, 진행 중인 연결은 끊기지 않고, 새 요청만 새 설정으로 라우팅됩니다.
이 동작 덕분에 트래픽 전환 시점에 사용자 입장에서 끊김이 거의 없습니다.

### 7-4. 헬스체크가 진짜 안전망이다

Blue-Green이 "무중단에 가까운" 이유는 사실 헬스체크에 기댑니다.

- 신규 컨테이너가 정상 응답할 때까지 트래픽을 안 보냄
- 응답 못 하면 전환을 멈추고 기존 컨테이너 유지

단순 HTTP 200 만 보는 것보다는,
**앱이 실제로 의존성(DB, Redis, 외부 API)에 닿을 수 있는지**까지 점검하는 헬스체크가 안전합니다.
이 부분은 다음 글에서 deploy.sh 와 함께 더 다룹니다.

### 7-5. 토이 프로젝트로도 운영 감각이 잡힌다

기능이 단순해도, 배포 흐름을 직접 짜보면 다음 같은 감각이 잡힙니다.

- "트래픽 수신 지점"과 "워크로드"를 분리해서 보는 사고
- 헬스체크 통과 전후로 trust 단계를 나누는 사고
- 롤백 가능한 단위로 배포를 쪼개는 사고

K8s나 ECS 같은 큰 도구로 옮겨가도 이 감각은 그대로 쓰입니다.

---

## 8. 마무리

Blue-Green이라는 단어를 처음 들었을 땐 "두 환경 번갈아 운영하기" 정도로만 이해했었습니다.
그런데 직접 손으로 짜보고 나니, 본질은 다음 한 줄에 가까웠습니다.

> 사용자 진입점은 고정하고,
> 그 뒤의 컨테이너는 교체 가능한 자원으로 다룬다.

이번 토이 프로젝트로 그 감각을 잡아두니,
이후에 K8s Deployment 의 rolling update 나 ALB target group 전환을 다룰 때도
같은 사고 방식을 그대로 적용할 수 있었습니다.

다음 글에서는 위에서 짧게 본 6단계 흐름을 실제로 자동화한 `deploy.sh` 의 내용,
즉 활성 색상 판단 / 헬스체크 / Nginx 설정 교체 / 이전 컨테이너 정리 같은 부분을 정리해보려고 합니다.
