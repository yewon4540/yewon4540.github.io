---
title: Loki 저장소를 emptyDir에서 hostPath PV로 전환 (retention 14일 + compactor)
layout: default
parent: Loki
grand_parent: 모니터링
nav_order: 1
written_at: 2026-05-19
---

# Loki 저장소를 emptyDir에서 hostPath PV로 전환 (retention 14일 + compactor)

단일 노드 K3s 클러스터에서 한동안 Loki를 띄워 두고 쓰고 있었는데,
어느 날 Grafana Explore에서 며칠 전 로그를 찾으려고 했더니 깨끗하게 비어 있었습니다.

알고 보니 Loki 파드가 어느 시점에 재시작됐고,
저장소가 `emptyDir` 로 잡혀 있어서 그 안에 들어 있던 로그가 다 날아간 상황이었습니다.

이번 글에서는 이 Loki를 hostPath 기반 영속 PV로 옮기고,
retention 14일과 compactor까지 함께 잡은 과정을 정리해보려고 합니다.

---

## 1. 발단

Grafana에서 며칠 전 LogQL 쿼리를 하나 돌렸을 때 응답이 비어 있는 걸 보고,
처음에는 단순히 쿼리가 이상한가 싶었습니다.

```text
{namespace="observability"} |= "error"
```

같은 쿼리를 시간 범위만 좁혀 봤더니 최근 몇 시간 로그는 정상으로 보였습니다.
즉, **최근 로그는 살아 있고 며칠 전 로그만 사라진 상태**였습니다.

Loki pod를 보니 RESTARTS가 적지 않게 누적되어 있었고,
원인을 따라가 보니 그동안 한 번씩 OOM이나 매니페스트 변경으로 pod가 재기동될 때마다,
**그 안의 `/loki` 디렉토리가 통째로 새로 만들어지고 있었습니다**.

확인해 보니 Deployment의 volume이 다음과 같이 잡혀 있었습니다.

```yaml
volumes:
  - name: config
    configMap:
      name: loki-config
  - name: data
    emptyDir: {}
```

`emptyDir`은 파드 라이프사이클에 묶이는 임시 볼륨이라,
**pod가 한 번 죽었다 살아나면 그 안의 데이터는 다 사라집니다**.

운영을 시작할 때는 "급한 대로 띄워두기"로 emptyDir이 잡혀 있었던 건데,
이 상태로 로그가 진짜 필요할 때 사라지는 걸 경험하고 나니
영속 스토리지로 옮길 때가 됐다는 게 분명해졌습니다.

---

## 2. 어떤 모양으로 가져갈 것인가

작업 목표는 단순했습니다.

- 저장소를 영속 볼륨(`hostPath` PV)으로 전환
- retention 14일 + compactor 활성화로 자동 정리
- 변경 후에도 같은 LogQL이 동작

단일 노드 K3s 환경이라 분산 스토리지를 끌어올 필요는 없었고,
호스트의 별도 마운트된 `/data` 디렉토리에 hostPath로 잡는 게 가장 단순했습니다.

대상 환경 요약은 다음과 같습니다.

| 항목 | 값 |
| --- | --- |
| Loki 이미지 | `grafana/loki:2.9.3` |
| 컨테이너 UID/GID | `10001:10001` (`loki:loki`) |
| 네임스페이스 | `observability` |
| Deployment replicas | 1 (단일 노드) |
| 호스트 데이터 경로 | `/data/log/loki` |
| PV 크기 / 정책 | 50Gi / Retain |
| retention | 336h (14일) |

---

## 3. 사전 점검

작업 직전에 세 가지를 확인했습니다.

### 3-1. `/data`가 실제로 별도 마운트인지

```bash
df -hT /data
```

`/` 와 같은 디바이스라면 디스크 분리 효과가 없습니다.
별도 LV/디스크에 마운트되어 있는 게 확인됐다면 안전합니다.

> fstab에 등록되지 않은 임시 마운트인 경우의 위험은
> [fstab 누락이 일으킨 K8s HostPath · 레지스트리 다층 장애 분석] 글에 정리해뒀습니다.

### 3-2. GitOps 관리 여부

ArgoCD나 Flux로 관리되는 매니페스트라면, ad-hoc apply가 self-heal로 되돌아갑니다.

```bash
kubectl get application -A 2>/dev/null | grep -iE "observ|loki"
```

해당 Application이 잡히면 변경분을 repo에 반영하고 sync 시키는 흐름으로 가야 합니다.

### 3-3. 현재 Loki volumes 백업

이번 patch는 volumes 배열을 통째로 교체하기 때문에,
기존에 추가로 붙어 있던 항목이 있다면 미리 파악해 둬야 합니다.

```bash
kubectl -n observability get deploy loki -o jsonpath='{.spec.template.spec.volumes}' | jq
```

이번 환경은 `config` + `data` 두 개라 단순했지만,
운영 환경에 따라 sidecar용 볼륨이 끼어 있는 경우도 있어서 한 번 보는 게 안전합니다.

---

## 4. Step 1 — 호스트 디렉토리 준비

Loki 컨테이너의 UID/GID가 `10001:10001`이므로, 호스트 디렉토리도 같은 소유자로 만들어 둡니다.
이 부분이 어긋나면 컨테이너가 PV에 쓰지 못하고 권한 에러로 죽습니다.

```bash
sudo install -d -m 0750 -o 10001 -g 10001 /data/log/loki
sudo install -d -m 0750 -o 10001 -g 10001 /data/log/loki/chunks
sudo install -d -m 0750 -o 10001 -g 10001 /data/log/loki/rules
sudo install -d -m 0750 -o 10001 -g 10001 /data/log/loki/compactor
```

확인:

```bash
sudo ls -la /data/log/loki
```

`loki:loki 0750` 으로 떨어지면 정상입니다.

---

## 5. Step 2 — PV / PVC 만들기

hostPath PV를 명시적으로 만들고, PVC가 그 PV에 정확히 binding 되도록 잡습니다.

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: loki-data-pv
  labels:
    app: loki
spec:
  capacity:
    storage: 50Gi
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
  hostPath:
    path: /data/log/loki
    type: DirectoryOrCreate
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: loki-data
  namespace: observability
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: ""
  volumeName: loki-data-pv
  resources:
    requests:
      storage: 50Gi
```

여기서 짚고 갈 포인트가 두 개 있습니다.

- `storageClassName: ""` 으로 비워두면 **default storage class 의 동적 프로비저너를 건너뛰고** 명시적으로 만든 PV에만 binding 됩니다. local-path-provisioner 가 깔린 클러스터에서 의도치 않은 PV가 자동 생성되지 않도록 막는 장치입니다.
- `persistentVolumeReclaimPolicy: Retain` 으로 두면 PVC 가 삭제되어도 PV와 호스트 디렉토리가 남습니다. 운영 데이터를 다루는 PV는 기본적으로 Retain 으로 두는 편이 안전했습니다.

PVC는 컨슈머(Loki pod)가 attach 하기 전까지 `Pending` 상태로 보일 수 있는데,
다음 단계의 Deployment patch 직후 자동으로 `Bound`로 전환되므로 그 시점에 멈춰서 디버깅할 필요는 없습니다.

---

## 6. Step 3 — ConfigMap에 retention과 compactor 추가

Loki는 retention만 잡는다고 실제로 데이터가 삭제되지 않습니다.
**compactor 블록을 같이 활성화해야** retention이 enforcement로 동작합니다.

핵심 변경 두 가지입니다.

- `limits_config.retention_period`: `336h` (14일)
- `compactor` 블록 신규 추가

```yaml
limits_config:
  retention_period: 336h
  ingestion_rate_mb: 10
  ingestion_burst_size_mb: 20
  max_streams_per_user: 10000
  max_line_size: 256kb

compactor:
  working_directory: /loki/compactor
  compaction_interval: 10m
  retention_enabled: true
  retention_delete_delay: 2h
  retention_delete_worker_count: 150
  delete_request_store: filesystem
```

여기서 한 가지 주의할 점:
**ConfigMap을 갈아 끼웠다고 Loki가 자동 reload 하지 않습니다**.
다음 단계의 Deployment patch가 새 pod를 띄울 때 새 설정으로 함께 뜨는 흐름입니다.

따라서 이 시점에 `kubectl rollout restart` 같은 명령을 따로 줄 필요는 없습니다.

---

## 7. Step 4 — Deployment patch

이제 실제로 Loki를 새 PV로 갈아 끼웁니다.

```bash
kubectl -n observability patch deploy loki --type=json -p='[
  {"op": "replace", "path": "/spec/strategy", "value": {"type": "Recreate"}},
  {"op": "replace", "path": "/spec/template/spec/volumes", "value": [
    {"name": "config", "configMap": {"name": "loki-config"}},
    {"name": "data", "persistentVolumeClaim": {"claimName": "loki-data"}}
  ]}
]'
```

여기서 가장 중요한 한 줄은 `strategy.type` 을 `Recreate` 로 바꾸는 부분입니다.

- 이번 PVC 는 `ReadWriteOnce` 라 동시에 두 pod가 attach 할 수 없음
- 기본값인 `RollingUpdate` 로 두면, 새 pod가 PVC attach 를 시도하는 동안 구 pod가 여전히 잡고 있어서 `Multi-Attach error` 가 떨어집니다
- `Recreate` 로 두면 구 pod terminate → 새 pod 시작 순서가 보장됨

대신 단일 노드 + replicas=1 환경이라 짧은 다운타임(약 30초)이 발생합니다.
이 다운타임이 운영상 허용 가능한지 미리 결정해 둘 필요가 있었습니다.

---

## 8. Step 5 — 검증

작업 직후 7가지를 차례로 봤습니다.

```bash
kubectl -n observability get pod -l app=loki
kubectl -n observability exec deploy/loki -- df -h /loki
kubectl -n observability exec deploy/loki -- ls -la /loki
kubectl -n observability exec deploy/loki -- wget -qO- http://localhost:3100/ready
kubectl -n observability logs deploy/loki --tail=100 | grep -iE "compactor|retention"
sudo ls -la /data/log/loki
sudo du -sh /data/log/loki
```

확인 포인트는 단순했습니다.

| 항목 | 정상 신호 |
| --- | --- |
| pod 상태 | `Running 1/1 RESTARTS=0` |
| `/loki` 마운트 | PV 디바이스가 잡혀 보임 |
| 디렉토리 권한 | `loki:loki 0750` |
| `/ready` 응답 | `ready` |
| compactor 로그 | `compactor` / `retention` 키워드 등장 |
| 호스트 디렉토리 | 몇 분 뒤 `chunks/` 아래 데이터 파일 적재 시작 |

마지막으로 Grafana Explore 에서 LogQL 한 줄을 돌려 신규 로그가 들어오는지 눈으로 확인했습니다.

---

## 9. 짚어두고 싶은 것들

### 9-1. `emptyDir`은 임시 저장소다

당연하지만 자주 잊는 부분입니다.

- `emptyDir`은 pod 라이프사이클에 묶이는 임시 볼륨
- pod가 한 번 죽었다 살아나면 그 안의 데이터는 사라짐
- 로컬 캐시나 임시 작업 공간이 아니면 운영 데이터를 담아두면 안 됨

이번 일이 좋은 교훈이었습니다.

### 9-2. retention 설정만으로는 자동 삭제 안 된다

Loki에서 retention_period만 잡으면 "조회 가능 기간"이 줄어들 뿐이고,
실제로 디스크의 chunk 가 삭제되는 건 **compactor 블록이 활성화되어 있을 때만** 일어납니다.

retention 설정이 보이는데 디스크가 계속 차오른다면 compactor 블록이 빠져 있는지 먼저 확인하면 됩니다.

### 9-3. RWO PVC + RollingUpdate 는 잘 안 어울린다

`ReadWriteOnce` PVC를 쓰는 Deployment 를 RollingUpdate 로 두면,
신구 pod가 동시에 attach 하려다가 `Multi-Attach error`가 나기 쉽습니다.

단일 replica 라면 `Recreate` 전략이 자연스럽고,
다중 replica가 필요한 컴포넌트라면 RWX 스토리지로 가거나 StatefulSet 패턴을 고려하는 게 맞습니다.

### 9-4. PV 는 Retain 으로 두는 게 안전

`Delete` 정책이면 PVC 가 사라질 때 PV와 호스트 디렉토리 데이터까지 정리됩니다.
운영 데이터를 다루는 경우는 작은 실수 한 번이 큰 손실로 이어질 수 있어서, 기본 정책은 `Retain` 으로 두고 정말 지울 때만 명시적으로 처리하는 흐름이 안전했습니다.

---

## 10. 마무리

처음 며칠 전 로그가 비어 있는 걸 봤을 때는 당황스러웠는데,
원인을 따라가다 보니 결국 "운영을 처음 시작할 때 임시로 잡아둔 emptyDir 한 줄"이 그대로 남아 있었던 것이었습니다.

> 운영 진입 시점에 임시로 잡아둔 설정은 의외로 오래 살아남는다.
> 정기적으로 다시 들여다보는 습관이 필요하다.

이번 작업 이후로는 retention 만큼은 안정적으로 유지되고 있고,
며칠 지난 로그도 정상적으로 조회 가능합니다.

다음 단계로 Promtail에 systemd-journal scraper 를 붙여서 호스트 로그까지 Loki 로 묶을 예정이고,
그 흐름은 별도 글로 이어서 정리해보려고 합니다.
