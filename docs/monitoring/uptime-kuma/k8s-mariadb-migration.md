---
title: Uptime Kuma Kubernetes 환경 운영 및 SQLite → MariaDB 마이그레이션
layout: default
parent: Uptime Kuma
grand_parent: 모니터링
nav_order: 1
written_at: 2026-03-27
---

# Uptime Kuma Kubernetes 환경 운영 및 SQLite → MariaDB 마이그레이션

- Kubernetes 환경에서 Uptime Kuma를 운영하려면 외부 DB(MariaDB/MySQL) 연결이 필요합니다.
- SQLite → MariaDB 마이그레이션 절차를 정리합니다.
- Kubernetes에서 외부 DB 자동 연결은 `.env` 파일로 관리합니다.

---

## 문제/상황

Uptime Kuma(이하 Kuma)는 기본적으로 SQLite를 저장소로 사용합니다.
SQLite는 로컬 디스크(컨테이너 내부)에 파일로 저장되기 때문에,
Kubernetes 환경에서는 파드 재생성 시 데이터 유실 위험이 있습니다.

기존 Docker/Compose 또는 직접 실행 방식에서 Kubernetes로 이전할 때
이 부분을 어떻게 처리할지가 핵심 이슈였습니다.

---

## 해결 방법 / 개요

이 글에서는 아래 내용을 정리합니다.

- SQLite 백업(노드 마운트) 방식의 한계와 포기 이유
- SQLite → MariaDB/MySQL 마이그레이션 절차
- Kubernetes 환경에서 외부 DB 연결 구성

---

## Kuma DB 비교

| 항목 | SQLite | MariaDB/MySQL |
| --- | --- | --- |
| 설치/운영 | 간단 (무설치) | 별도 서버/컨테이너 필요 |
| 확장성 | 단일 인스턴스 중심 | 다중 인스턴스/수평 확장 유리 |
| 내구성 | 로컬 파일 의존 | 외부 DB로 내구성 확보 |
| 백업 | 파일 백업 (잠금 주의) | mysqldump/스냅샷 등 다양 |
| 장애 복구 | 파일 복원 | RPO/RTO 설계 용이 |

---

## 1. SQLite 백업 (노드 마운트) 시도 → 보류

### 1-1) 전략

파드 삭제 시 `{path}/data/kuma.db`가 유실되므로,
저장 수준을 파드가 아닌 노드 디스크 또는 외부 스토리지로 올리는 방안을 검토했습니다.

### 1-2) 한계

**노드 마운트 방식**

- 워커 노드가 여러 개인 경우, 어떤 노드에 마운트할지 매 배포마다 수동 지정이 필요
- 특정 노드로만 배포되도록 고정하거나, 환경(prd/dev/stg)별 분기 설정이 추가로 필요
- 표준 CI/CD 흐름을 너무 많이 벗어나야 하는 구조

**외부 스토리지(S3 등) 방식**

- 네트워크 트래픽 및 Data transfer 비용 발생 가능
- cron 스케줄 백업이라면 파드 종료 시점과 맞지 않아 유실 구간 존재

### 1-3) 결론

Kubernetes 환경에서 Kuma를 안정적으로 운영하려면,
SQLite 대신 **외부 DB에 연동하는 방식**이 가장 현실적입니다.

---

## 2. SQLite → MariaDB/MySQL 마이그레이션

### 2-1) 전략

기존 SQLite에 저장된 Kuma 데이터를 MariaDB/MySQL로 이관합니다.

### 2-2) SQLite 데이터 백업

```bash
cd ${uptime-kuma-path}
cp -r ./data ./backup-data
```

### 2-3) 무결성 검증

```bash
docker run --rm -v ./data:/data nouchka/sqlite3 \
  sh -lc 'sqlite3 /data/kuma.db "PRAGMA integrity_check; PRAGMA wal_checkpoint(TRUNCATE); VACUUM;"'
```

### 2-4) MariaDB 연결 정보 구성

```bash
UPTIME_KUMA_DB_TYPE=mariadb
UPTIME_KUMA_DB_HOSTNAME=<DB_HOST>
UPTIME_KUMA_DB_PORT=<DB_PORT>
UPTIME_KUMA_DB_NAME=<DB_NAME>
UPTIME_KUMA_DB_USERNAME=<DB_USER>
UPTIME_KUMA_DB_PASSWORD=<DB_PASSWORD>
```

### 2-5) DB 최초 연결 (schema 자동 생성)

Kuma를 위 환경변수로 실행하면 최초 연결 시 schema가 자동 생성됩니다.
(UI에서 진행해도 동일한 결과)

최초 연결 후 Kuma를 종료(`ctrl + c`)합니다.

### 2-6) 데이터 이관 (`sqlite3-to-mysql`)

Python `sqlite3-to-mysql` 라이브러리를 사용합니다.

```bash
# SQLite 파일 위치 이동
cd {path}/data
ls -l ./kuma.db

# 가상환경 구성 및 라이브러리 설치
python3 -m venv .venv && source .venv/bin/activate
pip install -U pip sqlite3-to-mysql
```

**부모 테이블 먼저 이관**

```bash
sqlite3mysql \
  --sqlite-file ./kuma.db \
  --mysql-host <DB_HOST> --mysql-port <DB_PORT> \
  --mysql-database <DB_NAME> --mysql-user <DB_USER> --mysql-password '<DB_PASSWORD>' \
  --mysql-skip-create-tables --ignore-duplicate-keys -W \
  --sqlite-tables user,notification,monitor,tag,proxy,docker_host,"group",group_monitor,maintenance,incident,maintenance_notification
```

**전체 테이블 이관**

```bash
sqlite3mysql \
  --sqlite-file ./kuma.db \
  --mysql-host <DB_HOST> --mysql-port <DB_PORT> \
  --mysql-database <DB_NAME> --mysql-user <DB_USER> --mysql-password '<DB_PASSWORD>' \
  --mysql-skip-create-tables --without-foreign-keys --ignore-duplicate-keys -W
```

참고:

- 데이터를 1줄씩 insert하는 방식이므로 네트워크가 다르면 매우 느림
- 같은 네트워크 환경에서 진행 후 업로드하는 것이 현실적
  - 예시: 60만 rows 기준 → 외부 네트워크 17시간 vs 동일 네트워크 3분
- `--chunk 10000` 옵션을 추가하면 속도가 개선될 수 있음

---

## 3. Kubernetes 환경에서 외부 DB 연결 구성

파드가 재시작되더라도 항상 외부 DB에 연결될 수 있도록,
프로젝트 루트 디렉토리에 `.env` 파일을 구성합니다.

```bash
UPTIME_KUMA_DB_TYPE=mariadb
UPTIME_KUMA_DB_HOSTNAME=<DB_HOST>
UPTIME_KUMA_DB_PORT=<DB_PORT>
UPTIME_KUMA_DB_NAME=<DB_NAME>
UPTIME_KUMA_DB_USERNAME=<DB_USER>
UPTIME_KUMA_DB_PASSWORD=<DB_PASSWORD>
UPTIME_KUMA_DATA_PATH=<DATA_PATH>
```

이 `.env` 파일이 있으면 파드 재생성 시에도 자동으로 외부 DB에 연결됩니다.

---

## 정리

| 항목 | 내용 |
| --- | --- |
| SQLite 유지 | Kubernetes 환경에서 권장하지 않음 |
| 노드 마운트 | CI/CD 흐름 복잡도 증가로 비효율 |
| 외부 DB 전환 | 가장 안정적인 운영 구조 |
| 마이그레이션 | `sqlite3-to-mysql` 사용, 동일 네트워크 환경 권장 |
| Kubernetes 구성 | 루트 `.env` 파일로 외부 DB 자동 연결 |
