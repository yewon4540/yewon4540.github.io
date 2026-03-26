---
title: Docker 컨테이너 로그를 JSON 포맷으로 저장하기 (json-file 로그 드라이버)
layout: default
parent: Docker
grand_parent: 인프라
nav_order: 5
written_at: 2026-03-26
---

# Docker 컨테이너 로그를 JSON 포맷으로 저장하기 (json-file 로그 드라이버)

운영 환경에서 Docker 컨테이너 로그를 수집하고 분석할 때, 기본 로그 드라이버만 사용하면 구조화된 형식이 아니어서 파싱이 복잡합니다.
JSON 포맷으로 저장하면 Fluentd나 Logstash 같은 로그 수집 도구에서 쉽게 처리할 수 있습니다.

---

## 문제 상황

기본적으로 Docker는 컨테이너의 `stdout`/`stderr`을 텍스트로 저장합니다.

- 로그에 타임스탬프, 스트림 정보가 자동으로 포함되지 않음
- 로그 수집 도구에서 파싱하기 어려움
- 로그 로테이션 설정 불가능

---

## 해결 방법

JSON 포맷 로그 드라이버를 사용하면:

- 구조화된 JSON 형식으로 저장
- 타임스탐프, 스트림(stdout/stderr) 정보 자동 포함
- 파일 크기 기반 로테이션 설정 가능
- 로그 수집 도구와 호환

---

## 아키텍처

```
[컨테이너 stdout/stderr] → [json-file 드라이버] → [/var/lib/docker/containers/.../...json.log]
                                                     ↓
                                        [Fluentd가 수집]
```

---

## 사전 준비

- Docker 설치
- 컨테이너 실행 권한
- logjson 포맷 이해

---

## 1. JSON 포맷 로그 드라이버 활성화

### 1-1) docker run으로 실행할 때

```bash
docker run \
  --log-driver json-file \
  --log-opt max-size=10m \
  --log-opt max-file=3 \
  -d nginx:latest
```

옵션 설명:

- `--log-driver json-file`: JSON 포맷 드라이버 사용
- `--log-opt max-size=10m`: 한 파일 최대 크기 10MB
- `--log-opt max-file=3`: 최대 3개 파일 보관 (총 30MB)

### 1-2) docker-compose로 실행할 때

```yaml
version: '3'

services:
  web:
    image: nginx:latest
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

---

## 2. 로그 확인해보기

```bash
# 컨테이너 ID 확인
docker ps

# JSON 형식 로그 확인
docker logs <container_id>

# 실제 저장된 파일 위치
cat /var/lib/docker/containers/<container_id>/<container_id>-json.log | jq .
```

JSON 로그 구조:

```json
{
  "log": "GET / HTTP/1.1\n",
  "stream": "stdout",
  "time": "2026-03-26T10:30:45.123456789Z"
}
```

- `log`: 실제 로그 내용
- `stream`: 출력 스트림 (stdout/stderr)
- `time`: ISO 8601 형식 타임스탬프

---

## 3. 기본 로그 드라이버 설정 ('Daemon.json')

모든 컨테이너에 JSON 드라이버를 기본설정하려면 Docker 데몬 설정을 변경합니다.

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3",
    "labels": "production"
  }
}
```

설정 파일 위치:

- Linux: `/etc/docker/daemon.json`
- Mac (Docker Desktop): Preferences → Docker Engine
- Windows: 유사한 경로

변경 후:

```bash
# Docker 데몬 재시작
sudo systemctl restart docker

# 또는 Mac
killall Docker  # Docker Desktop 종료 후 다시 실행
```

---

## 참고

- 로그 크기 제한을 너무 작게 설정하면 중요 로그가 남지 않음 (권장: 10m ~ 100m)
- 파일 수를 너무 적게 하면 로테이션이 자주 발생 (권장: 3 ~ 10개)
- 운영 환경에서는 반드시 로그 수집 도구(Fluentd, ELK 등)와 함께 사용
