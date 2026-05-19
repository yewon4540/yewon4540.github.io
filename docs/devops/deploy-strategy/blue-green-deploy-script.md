---
title: Blue-Green 배포 스크립트 deploy.sh 분해 (활성 색상 판단 · 헬스체크 · proxy_pass 전환)
layout: default
parent: 배포 전략
grand_parent: Devops
nav_order: 2
written_at: 2026-05-19
---

# Blue-Green 배포 스크립트 deploy.sh 분해 (활성 색상 판단 · 헬스체크 · proxy_pass 전환)

[Docker Compose + Nginx reverse proxy로 만든 가장 단순한 Blue-Green 배포 구조] 글에서
다음과 같은 6단계 흐름을 정리했습니다.

```text
1. 현재 활성 색상 확인
2. 반대 색상 컨테이너 실행
3. 신규 컨테이너 헬스체크
4. Nginx default.conf 교체
5. Nginx reload
6. 이전 컨테이너 종료
```

이번 글에서는 이 6단계를 실제로 자동화한 `deploy.sh`를 한 줄씩 분해하면서,
**왜 그 순서로 짰는지 / 어떤 함정을 피하기 위해 그렇게 짰는지**를 정리해보려고 합니다.

---

## 1. 발단

BG 구조를 손으로 띄워 보고 나니, 매번 다음 작업을 반복하고 있었습니다.

- 어느 색상이 떠 있는지 `docker ps`로 확인
- 반대 색상을 `compose up`
- `curl /health` 로 헬스체크
- `default.conf` 의 `proxy_pass` 줄 수정
- `nginx reload`
- 이전 색상 `compose down`

이걸 매번 손으로 하기엔 너무 단순한 반복이라,
한 번에 처리할 수 있는 스크립트 하나로 묶어두는 게 자연스러웠습니다.

목표는 단순했습니다.

- 인자 없이 실행 가능 (현재 상태를 스크립트가 알아서 판단)
- 헬스체크 실패 시 트래픽 전환을 진행하지 않고 멈춤
- 초기 배포(아무것도 안 떠 있는 상태)와 일반 배포 모두 처리

---

## 2. 스크립트의 책임 범위 먼저 정해두기

코드를 읽기 전에, deploy.sh 가 책임지는 범위와 책임지지 않는 범위를 짚어둘 필요가 있습니다.

| 책임 O | 책임 X |
| --- | --- |
| 활성 색상 판단 | 코드 받아오기 (`git pull` 등은 외부에서) |
| 신규 컨테이너 빌드 / 실행 | 이미지 레지스트리 push |
| 헬스체크 폴링 | 정교한 의존성 헬스체크 (DB/Redis 등 — 개선 포인트) |
| Nginx 설정 교체 + reload | Nginx 자체 설치 |
| 이전 컨테이너 정리 | 디스크 청소, 이미지 prune |

스크립트가 **트래픽 전환에만 집중**하도록 잘라두면, 다른 워크플로(Jenkins 파이프라인 등)에서 이 스크립트를 한 단계로 호출하기 편해집니다.

---

## 3. 시작 부분 — 안전한 실행 환경

스크립트는 다음으로 시작합니다.

```bash
#!/bin/bash
set -e

cd "$(dirname "$0")"
```

두 줄이지만 의미가 큽니다.

- `set -e`: 어느 단계든 실패하면 그 시점에 멈춥니다. Blue-Green은 전환을 멈춰야 안전한 상황이 자주 나오기 때문에 기본 동작이 됩니다.
- `cd "$(dirname "$0")"`: 스크립트가 위치한 디렉토리로 이동합니다. `cron`, Jenkins agent 등 다른 작업 디렉토리에서 호출돼도 항상 같은 위치에서 동작하게 됩니다.

운영 스크립트를 짤 때 이 두 줄은 거의 반사적으로 넣는 편입니다.

---

## 4. Docker 네트워크 보장

```bash
if ! docker network ls | grep -q draw_net; then
  docker network create draw_network
fi
```

Blue/Green 컨테이너와 Nginx 컨테이너가 같은 네트워크에 묶여 있어야
Nginx가 컨테이너 이름으로 내부 통신할 수 있습니다.

스크립트가 처음 실행될 때는 네트워크가 없을 수 있으니,
**없으면 만들고 있으면 건너뛰는 멱등(idempotent) 패턴**으로 잡아 둡니다.

> 운영 스크립트의 모든 사전 준비 단계는 가능하면 멱등하게.
> 두 번 실행해도 결과가 같아야, 어디서 멈춰도 다시 돌릴 수 있습니다.

---

## 5. 활성 색상 판단

여기가 Blue-Green 스크립트의 진짜 핵심입니다.

```bash
if docker ps --format '{{.Names}}' | grep -q draw_blue; then
  CURRENT=blue
  NEXT=green
elif docker ps --format '{{.Names}}' | grep -q draw_green; then
  CURRENT=green
  NEXT=blue
else
  CURRENT=none
  NEXT=blue
fi
```

판단 기준은 단순합니다.

- `draw_blue`가 떠 있으면 다음은 green
- `draw_green`이 떠 있으면 다음은 blue
- 둘 다 없으면 초기 배포 — 첫 색상은 blue로 시작

`docker ps --format '{{.Names}}'`는 컨테이너 이름만 깔끔하게 떨어뜨려 줘서,
`grep` 한 줄로 활성 색상을 판단하기 좋습니다.

> Compose 파일을 색상별로 나눠 둔 이유가 이 단계에서 살아납니다.
> 활성 색상 = "지금 떠 있는 컨테이너 이름"으로 단순 판단 가능.

---

## 6. 신규 컨테이너 실행

```bash
docker-compose -f ${NEXT}.yml up -d --build
```

- `-f ${NEXT}.yml`: 다음 색상의 Compose 파일을 지정
- `-d`: 백그라운드 실행
- `--build`: 이미지 빌드 강제 (변경된 코드가 그대로 반영되도록)

이 시점에는 기존 색상 컨테이너가 여전히 떠 있고 Nginx도 기존 색상을 가리키고 있어서,
사용자 트래픽은 그대로 기존 컨테이너로 흐릅니다.

신규 컨테이너는 트래픽을 받지 않은 채로 부팅됩니다.

---

## 7. 헬스체크 폴링

```bash
HEALTH_OK=false

for i in $(seq 1 10); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5179/health || true)
  if [ "$STATUS" = "200" ]; then
    HEALTH_OK=true
    break
  else
    sleep 5
  fi
done

if [ "$HEALTH_OK" != "true" ]; then
  echo "헬스체크 실패! 배포 중단"
  exit 1
fi
```

여기서 작은 디테일들이 모여 안정성을 만듭니다.

- **최대 10회 × 5초 = 50초** 동안 대기. 앱의 콜드 스타트 시간을 감안한 값.
- `curl ... || true`: curl 자체 실패도 200 이외로 취급해서 재시도 (네트워크가 일시적으로 안 풀려도 OK)
- 한 번이라도 200이 떨어지면 즉시 빠져나옴 (`break`)
- 끝까지 200을 못 받으면 `exit 1` 로 스크립트 종료 — `set -e`와 함께 호출자에게 실패가 전달됨

**중요한 건 헬스체크 실패 시 트래픽 전환을 진행하지 않는다는 점**입니다.
신규 컨테이너는 떠 있지만 사용자 트래픽은 여전히 기존 컨테이너가 받습니다.
즉, 운영 측면에서는 사실상 무중단입니다.

---

## 8. Nginx 설정 교체

```bash
sed -i "s|proxy_pass .*|proxy_pass http://draw_${NEXT}:5179/;|" \
  nginx.conf/conf.d/default.conf
```

`sed -i`로 `proxy_pass` 줄을 신규 색상으로 교체합니다.

- 구분자로 `|`를 쓴 건 URL에 `/`가 들어가서 슬래시 충돌을 피하기 위함
- `proxy_pass .*` 패턴 매칭으로 줄 전체를 갈아 끼움

이 시점에 디스크의 default.conf는 신규 색상으로 바뀌어 있지만,
Nginx 프로세스는 아직 기존 설정을 들고 돌아가고 있습니다.
즉, **트래픽은 여전히 기존 색상이 받고 있습니다**.

---

## 9. Nginx 재기동

```bash
if docker ps --format '{{.Names}}' | grep -q web_server; then
  docker-compose -f nginx.yml restart
else
  docker-compose -f nginx.yml up -d
fi
```

이번 스크립트는 `nginx -s reload` 대신 `compose restart`를 사용합니다.

| 방식 | 동작 |
| --- | --- |
| `nginx -s reload` | 워커만 graceful 교체, 마스터는 유지 |
| `compose restart` | 컨테이너 자체를 재기동 (짧은 끊김 가능) |

좀 더 부드러운 전환을 원한다면 `nginx -s reload` 쪽이 좋고,
운영 스크립트의 단순함을 우선한다면 `restart` 도 무난합니다.

이 토이 프로젝트는 후자를 골랐고, 다음에 만든다면 reload 패턴으로 바꿔보고 싶은 부분입니다.

`web_server`가 떠 있지 않은 초기 배포 상황도 처리해서,
한 스크립트로 "최초 배포 + 일반 배포"를 모두 다룰 수 있게 했습니다.

---

## 10. 이전 컨테이너 종료

```bash
if [ "$CURRENT" != "none" ]; then
  docker-compose -f ${CURRENT}.yml down
fi
```

트래픽이 신규 컨테이너로 넘어간 뒤, 이전 컨테이너를 내립니다.

`CURRENT=none`(초기 배포) 인 경우만 건너뛰는 게 포인트입니다.
스크립트 한 개로 초기 배포까지 처리하기 위한 분기입니다.

이 시점 이후로 사용자 트래픽은 신규 색상이 받고 있고,
이전 색상은 깔끔하게 정리되었습니다.

---

## 11. 짚어두고 싶은 것들

### 11-1. 스크립트 첫 두 줄(`set -e` + `cd`)은 반사적으로 넣자

- `set -e`: 실패 시 즉시 중단 — Blue-Green은 중간에 멈춰야 안전한 시나리오가 많음
- `cd "$(dirname "$0")"`: 호출 디렉토리에 영향받지 않음

운영 스크립트의 안정성은 이 두 줄이 절반 정도 책임집니다.

### 11-2. 사전 준비는 멱등하게

네트워크 생성, Nginx 컨테이너 존재 확인 — 두 번 실행해도 같은 결과가 나오게 만들어 두면,
어디서 멈춰도 그냥 다시 돌리면 됩니다.
배포 스크립트에서 멱등성은 자기 자신을 한 번 더 안전하게 만들어 주는 장치입니다.

### 11-3. 헬스체크가 진짜 안전망

현재 스크립트의 헬스체크는 `/health` 200만 봅니다.
이것만으로도 "프로세스가 떴는가"는 확인되지만, 운영 관점에서는 한 단계 더 가는 게 안전합니다.

- DB 연결 확인
- Redis ping
- 외부 의존성 호출

이걸 `/health` 엔드포인트 안에서 같이 체크하도록 만들면,
**컨테이너는 떴는데 의존성이 안 잡힌 채로 트래픽을 받는 상황**을 막을 수 있습니다.

### 11-4. 명시적 롤백은 별도로

이번 스크립트는 신규 배포 실패 시 트래픽 전환만 안 합니다.
다만 "이전 배포로 즉시 되돌리는" 명시적 롤백 로직은 빠져 있습니다.

운영 환경이라면 다음을 추가하면 좋을 것 같습니다.

- 직전 default.conf 백업 보관
- 실패 시 백업 복원 + Nginx reload
- 배포 이력(언제, 어느 색상으로, 결과) 기록

지금 구조에서 이걸 더 얹는 건 어려운 일은 아니지만,
"토이 프로젝트 수준에서 어디까지 다룰지" 는 한 번 끊고 가는 게 좋다고 봤습니다.

### 11-5. 같은 스크립트를 Jenkins가 호출한다

이 스크립트의 가장 큰 장점은 단순함입니다.
인자 하나 없이 실행되고, exit code로 성공/실패가 명확합니다.
이 두 가지 덕분에 Jenkins 파이프라인이 단 한 줄로 호출할 수 있습니다.

```text
sh 'cd /home/deploy/random-draw-bluegreen-deploy && bash deploy.sh'
```

Jenkins 자동화 부분은 다음 글에서 이어서 정리합니다.

---

## 12. 마무리

배포 스크립트는 평소엔 잘 들여다보지 않다가 사고가 났을 때 한 줄씩 읽게 됩니다.
그때 다시 봤을 때 **읽기 쉽고, 어디서 멈춰도 다시 돌릴 수 있는 형태**로 짜두는 게 중요합니다.

이번 deploy.sh 의 흐름을 한 줄로 정리하면 이렇습니다.

> 활성 색상을 알아서 판단해서 반대 색상을 띄우고,
> 헬스체크가 통과한 경우에만 트래픽을 옮긴 뒤,
> 이전 색상은 깔끔하게 정리한다.

이 흐름이 외부에서 보면 단순한 한 줄짜리 호출이 되고,
내부에서 보면 `set -e` / 멱등성 / 헬스체크 폴링 / 실패 시 멈춤 같은 여러 안전 장치가 쌓여 있는 형태가 됩니다.

뭐... 실제로 이 스크립트로 배포를 하지는 않겠다만, 기본적인 blue-green을 직관적으로 이해하고 설명하기 위한 스크립트로서 가치가 있다고 생각합니다
