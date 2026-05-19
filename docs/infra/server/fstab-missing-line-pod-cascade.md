---
title: fstab 누락이 일으킨 K8s HostPath · 레지스트리 다층 장애 분석
layout: default
parent: Server
grand_parent: 인프라
nav_order: 5
written_at: 2026-05-19
---

# fstab 누락이 일으킨 K8s HostPath · 레지스트리 다층 장애 분석

폐쇄망 환경의 단일 노드 k3s 클러스터에서 노드가 한 번 재부팅됐고,
다음 날 출근해서 클러스터 상태를 보다가 한 네임스페이스의 파드 14개가 전부 CrashLoopBackOff로 누워 있는 걸 봤습니다.

처음에는 단순히 이미지 풀이 안 됐겠거니 싶었는데,
원인을 따라가다 보니 시작점은 의외로 한 줄이었습니다.

> `/etc/fstab`에 LV 마운트가 등록되어 있지 않았다.

이번 글에서는 그 한 줄이 어떻게 K8s 파드 14개를 동시에 죽이는 데까지 연결됐는지를 정리해보려고 합니다.

---

## 1. 발단

아침에 클러스터 상태를 보다가 한 네임스페이스의 파드 상태가 이상했습니다.

```bash
kubectl get pods -n app
```

14개 파드 전부 `CrashLoopBackOff`,
RESTARTS는 200을 훌쩍 넘어가 있었습니다.

`describe`로 보니 공통 증상은 단순했습니다.

```text
Failed to pull image "registry.example.com:30500/app-core:latest":
rpc error: ... 400 Bad Request
```

전부 이미지 풀 실패였습니다.

여기서 든 첫 의문은 단순했습니다.

> 어제까지 멀쩡히 돌던 이미지인데,
> 왜 갑자기 400 Bad Request가 떨어지지?

---

## 2. 노드와 컨트롤 플레인 상태 먼저

이미지 풀 실패는 보통 다음 셋 중 하나입니다.

- 이미지가 실제로 없거나
- 레지스트리에 닿지 않거나
- 인증서/프로토콜이 어긋났거나

그런데 그 전에 노드 자체가 멀쩡한지부터 확인해야 했습니다.

```bash
kubectl get nodes
systemctl status k3s
```

노드는 `Ready`였고 k3s 서비스도 `active (running)`이었습니다.
즉, "노드가 죽어서 파드가 다 떨어진" 시나리오는 아니었습니다.

`journalctl -u k3s -n 100`도 잠깐 봤지만 평소처럼 reconcile 로그만 흐르고 있었고,
컨트롤 플레인 자체에 큰 문제는 없어 보였습니다.

남은 건 레지스트리 쪽이었습니다.

---

## 3. 레지스트리부터 들여다보기

레지스트리는 클러스터 안에 띄워둔 self-hosted 였습니다.
HostPath 볼륨으로 `/data/registry` 경로를 사용하는 단순한 구조입니다.

먼저 catalog부터 찍어봤습니다.

```bash
curl -k https://registry.example.com:30500/v2/_catalog
```

응답은 이렇게 떨어졌습니다.

```json
{"repositories":[]}
```

저장소가 비어 있다고 답하고 있었습니다.

머릿속이 잠깐 멈췄습니다.

> 어제까지 8개 레포가 들어 있던 레지스트리가
> 왜 빈 상태로 답하지?

설마 진짜로 다 날아갔나 싶어서, 호스트에서 실제 디렉토리를 직접 들여다봤습니다.

```bash
sudo ls /data/registry/docker/registry/v2/repositories/
```

그런데 디렉토리는 비어 있는데
`df -h /data`를 보면 사용량이 평소보다 훨씬 작았습니다.

**1.1 TB 가까이 쓰고 있어야 할 `/data`가, 빈 디렉토리처럼 보이고 있었습니다.**

---

## 4. `/data`가 마운트되어 있는지 확인

여기서부터 시선이 K8s 바깥, 호스트 OS 쪽으로 옮겨갔습니다.

```bash
findmnt /data
df -hT /data
lsblk
```

`findmnt /data`는 아무것도 출력하지 않았습니다.
즉, `/data`는 **마운트되어 있지 않은 상태**였습니다.

`lsblk`로 보니 LV는 멀쩡히 존재하고 있었습니다.

```text
NAME                          SIZE TYPE
sda                           1.5T disk
└─sda1                        1.5T part
  └─data--vg-lv_data          1.3T lvm
```

LV는 살아 있는데 마운트만 풀려 있는 상태였습니다.

그제서야 짚인 게 있었습니다.

> 어제 노드가 재부팅됐다.
> 재부팅 후에 `/data`가 다시 마운트됐어야 했는데, 안 됐다.

자동 마운트는 `/etc/fstab`이 책임지는 영역입니다.
바로 fstab을 확인했습니다.

```bash
cat /etc/fstab
```

그리고 `/data` 관련 줄이 없었습니다.

---

## 5. 빈 디렉토리 위에 떠버린 레지스트리 파드

여기서부터는 흐름이 보이기 시작했습니다.

레지스트리 파드는 HostPath 볼륨을 `DirectoryOrCreate`로 잡고 있습니다.

```yaml
volumes:
  - name: registry-data
    hostPath:
      path: /data/registry
      type: DirectoryOrCreate
```

`DirectoryOrCreate`는 경로가 없으면 만들어 주는 옵션입니다.

재부팅 직후 `/data`가 마운트되어 있지 않은 상태에서 레지스트리 파드가 다시 떴고,
그 시점에서 호스트 입장에서 `/data/registry`는 "원래 LV 위에 있던 1.1TB짜리 디렉토리"가 아니라
"루트 파일시스템 위에 막 만들어진 빈 디렉토리"였습니다.

> 디스크에 들어 있는 1.1TB의 데이터는 멀쩡히 살아 있다.
> 다만 그 위에 LV가 마운트되어 있지 않아서, 빈 디렉토리에 가려져 보이지 않을 뿐이다.

레지스트리 입장에서는 빈 디렉토리를 catalog 인덱스 대상으로 잡고 기동했고,
당연히 catalog 응답이 `[]`로 떨어졌습니다.

---

## 6. 그런데 왜 400 Bad Request였을까

이 부분이 처음에 가장 헷갈렸던 지점입니다.

이미지가 없다면 보통 `404 NotFound`가 떨어져야 자연스럽습니다.
그런데 응답은 `400 Bad Request`였습니다.

원인은 containerd가 레지스트리를 찾아갈 때의 fallback 동작에 있었습니다.

k3s가 `/etc/rancher/k3s/registries.yaml`을 기반으로 자동 생성하는 hosts.toml은 대략 이런 모양이었습니다.

```toml
server = "http://localhost:30500/v2"

[host."https://registry.example.com:30500/v2"]
  capabilities = ["pull", "resolve"]
  ca = ["/data/jeju-ca/ca.crt"]
```

이 설정의 의미는 이렇습니다.

- 평소: HTTPS mirror(`registry.example.com:30500`)로 resolve / pull
- 그 mirror에서 resolve 실패가 떨어지면 primary인 `http://localhost:30500`로 폴백

여기서 두 가지 일이 동시에 벌어졌습니다.

1. HTTPS mirror는 catalog가 비어 있으니 manifest resolve 실패
2. fallback으로 들어간 primary는 `http://`인데, 실제 레지스트리는 HTTPS만 받음 → 400 Bad Request

즉, "이미지가 없다"가 아니라 "fallback 끝에서 protocol이 어긋난 결과"가 400으로 보였던 것입니다.

이 시점에서는 추가로 손댈 게 없었습니다.
**원래 마운트만 정상이었으면 catalog가 비지 않았을 거고, fallback 자체가 발생하지 않았을 일**이었기 때문입니다.

---

## 7. 복구 절차

여기까지 정리되고 나니 절차는 명확해졌습니다.

### 7-1. fstab에 영구 마운트 등록

먼저 LV의 UUID를 확인합니다.

```bash
sudo blkid /dev/mapper/data--vg-lv_data
```

그리고 `/etc/fstab`에 한 줄을 추가합니다.

```text
/dev/mapper/data--vg-lv_data /data xfs defaults 0 0
```

UUID 기반으로 잡아주는 것도 좋습니다.

```text
UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx /data xfs defaults 0 0
```

### 7-2. 실제 마운트

```bash
sudo mount -a
findmnt /data
df -hT /data
```

`findmnt /data`에서 디바이스가 보이면 정상입니다.
`df`로 사용량이 1.1TB 가까이 다시 잡히는 걸 확인했습니다.

### 7-3. 레지스트리 파드 재시작

`/data`가 다시 마운트된 상태에서 레지스트리 파드를 한 번 재기동했습니다.

```bash
kubectl delete pod -n registry -l app=registry
```

이번에는 HostPath가 원래의 1.1TB 디렉토리를 가리키게 됐고,
파드가 다시 뜬 직후의 catalog는 정상으로 돌아왔습니다.

```bash
curl -k https://registry.example.com:30500/v2/_catalog
```

```json
{"repositories":["app-core","app-frontend","app-gateway","app-sso","..."]}
```

### 7-4. 앱 파드 전체 재생성

레지스트리가 정상이면 이미지 풀은 자연스럽게 풀립니다.

```bash
kubectl delete pods -n app --all
```

40초 정도 지나니 14개 파드가 전부 `Running 1/1 RESTARTS=0` 으로 정렬됐습니다.

---

## 8. 짚어두고 싶은 것들

### 8-1. 수동 mount만으로는 절대 끝이 아니다

이번 일의 시작점은 결국 "수동 마운트만 하고 fstab에는 등록하지 않은 LV" 였습니다.

운영 중에는 너무 자연스럽게 마운트가 잡혀 있어서 인식하지 못하지만,
재부팅 한 번이면 그 가정이 무너집니다.

`mount` 명령으로 임시 마운트를 한 뒤에는 **반드시 fstab 등록까지 한 세트로 처리**해야 한다는 걸 다시 한 번 새겼습니다.

### 8-2. HostPath + DirectoryOrCreate의 함정

`DirectoryOrCreate`는 분명히 편한 옵션입니다.
경로가 없으면 알아서 만들어 주니까,
파드를 띄울 때 호스트 디렉토리 존재 여부를 신경 쓸 필요가 없습니다.

그런데 이번처럼 **원래 마운트되어 있어야 할 경로가 안 마운트된 상황**에서는,
빈 디렉토리를 만들어 그 위에 파드를 띄워버립니다.

호스트 입장에서는 "원본 데이터는 그대로인데 안 보이게 가려진" 상태가 되고,
앱 입장에서는 "저장된 게 아무것도 없는 새 디렉토리"가 됩니다.

운영 중요한 데이터를 담는 HostPath라면 차라리 `Directory`로 두는 것도 방법입니다.
경로가 없으면 파드가 못 뜨고 멈춰주니, 오히려 빨리 알아챌 수 있습니다.

### 8-3. 한 줄짜리 누락은 종종 다층 장애로 번진다

이번 사고에서 표면 증상은 "이미지 풀 실패"였습니다.
그러나 한 꺼풀씩 벗기면 다음과 같이 전개됐습니다.

```text
fstab 한 줄 누락
   ↓
재부팅 후 /data 미마운트
   ↓
빈 /data/registry 위에 레지스트리 파드 기동
   ↓
catalog 빈 응답
   ↓
containerd mirror resolve 실패
   ↓
HTTP primary로 폴백 → HTTPS 레지스트리에서 400
   ↓
앱 파드 14개 ImagePullBackOff / CrashLoopBackOff
```

문제가 표면으로 드러난 위치(파드)와 실제 원인 위치(OS 마운트)가 멀어질수록,
"어디부터 봐야 하는가"가 모호해집니다.

특히 한 노드짜리 폐쇄망 클러스터에서는 호스트 OS 상태가 K8s 동작에 그대로 비치기 때문에,
파드 레벨 증상만 보지 말고 **호스트의 LV / 마운트 / fstab / journald를 같이 보는 습관**이 필요하다는 걸 다시 느꼈습니다.

### 8-4. 재부팅 후 점검 리스트

이번 일을 계기로 노드 재부팅 직후에 한 번씩 점검할 항목을 짧게 정리해두었습니다.

| 항목 | 확인 명령 |
| --- | --- |
| 주요 마운트 상태 | `findmnt /data` / `df -hT` |
| fstab 등록 여부 | `grep <mount> /etc/fstab` |
| HostPath 기반 파드의 데이터 디렉토리 | 호스트에서 실제 디렉토리 사용량 확인 |
| 레지스트리 catalog | `curl /v2/_catalog` |
| 앱 네임스페이스 파드 상태 | `kubectl get pods -n <app-ns>` |

특히 "HostPath를 쓰는 파드의 데이터 디렉토리"가 이번 일에서 가장 늦게 알아챈 항목이었습니다.

---

## 9. 마무리

처음에는 단순히 "이미지가 안 풀린다"였고,
그 다음에는 "레지스트리가 비어 보인다"였고,
결국 도달한 곳은 fstab의 한 줄 누락이었습니다.

> 잘 도는 인프라일수록 작은 누락이 잘 보이지 않고,
> 누락은 보통 재부팅 같은 흔치 않은 이벤트에서 표면화된다.

이번 일을 통해 fstab 등록을 마운트 절차와 분리해서 생각하지 않게 됐고,
HostPath 기반 파드에 대해서도 "이 디렉토리가 마운트가 풀리면 어떤 모습이 될까"를 한 번 더 떠올리게 됐습니다.

표면 증상에서 두세 단계 떨어진 곳에 진짜 원인이 있는 경우가 적지 않다는 걸,
이번 14개 파드가 다시 알려줬습니다.
