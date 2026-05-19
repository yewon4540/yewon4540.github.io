---
title: K3s API 503 ServiceUnavailable 첫 진단 5종과 표준 복구 (k3s-killall.sh)
layout: default
parent: k3s
grand_parent: Kubernetes
nav_order: 2
written_at: 2026-05-19
---

# K3s API 503 ServiceUnavailable 첫 진단 5종과 표준 복구 (k3s-killall.sh)

폐쇄망의 single-node K3s 클러스터에서 노드가 한 번 재부팅된 뒤,
`kubectl get nodes` 한 줄이 안 먹히는 상황을 마주한 적이 있습니다.

처음에는 단순한 일시적 문제로 보였는데,
같은 명령을 몇 번 더 쳐도 계속 같은 응답이 떨어지면서 분위기가 조금씩 무거워졌습니다.

이번 글에서는 그때 어떤 순서로 상태를 봤고,
표준적인 복구가 왜 `systemctl restart`가 아니라 `k3s-killall.sh`에서 시작하는지를 정리해보려고 합니다.

---

## 1. 발단

재부팅이 끝났다고 해서 SSH로 들어가 평소처럼 `kubectl`을 친 순간,
다음과 같은 응답이 떨어졌습니다.

```text
E0507 ... memcache.go:265] couldn't get current server api group list:
the server is currently unable to handle the request
Error from server (ServiceUnavailable):
the server is currently unable to handle the request
```

503 ServiceUnavailable.

이 응답이 의미하는 바는 의외로 명확합니다.

- TCP 자체는 닿고 있다 (커넥션은 맺어졌다)
- HTTP 응답까지는 받았다
- 다만 API 서버가 "지금은 처리할 수 없다"고 답하고 있다

즉, **k3s 프로세스 자체는 살아 있지만 ready 상태가 아니다**라는 신호였습니다.

`systemctl status k3s`도 `active (running)`이라고 답하고 있었습니다.
프로세스는 살아있는데 서비스만 안 받는 상태였습니다.

---

## 2. 그냥 restart 하면 되지 않을까?

가장 먼저 떠오른 건 단순한 방법이었습니다.

```bash
sudo systemctl restart k3s
```

그런데 이 명령이 stop 단계에서 한참을 멈춰 있었습니다.
`Ctrl+C`로 취소한 뒤 `systemctl list-jobs`를 보니
`k3s.service` 의 stop 작업이 그대로 대기 중이었습니다.

> 컨테이너 런타임이나 네트워크 정리가 깔끔히 끝나지 않은 상태에서
> systemd가 stop을 기다리며 멈춰 있다.

K3s는 단일 바이너리 안에 server / containerd / kubelet / proxy가 같이 들어 있는 구조라,
`systemctl restart`로 stop 시퀀스를 정상적으로 마치려면 안에 있는 모든 컴포넌트가 시그널에 반응해야 합니다.

어딘가 한 곳이라도 hang에 빠지면 systemctl이 무한정 기다립니다.

여기서 두 가지를 알게 됐습니다.

- 이미 ready 상태가 아닌 K3s를 `systemctl restart`로 되살리려고 하면 막힐 가능성이 높다
- 표준 절차는 `k3s-killall.sh`로 전체를 한 번에 내린 뒤 `systemctl start k3s` 로 다시 띄우는 것

다만 이건 손대기 전 안전장치를 먼저 챙긴 다음의 이야기입니다.

---

## 3. 손대기 전에 먼저 챙긴 것

K3s 단일 노드 + 내장 etcd 구성에서는,
손대기 전에 etcd 스냅샷 한 번 만들어 두는 게 가장 저렴한 안전장치였습니다.

```bash
sudo k3s etcd-snapshot save --name pre-recover
```

이게 의미가 있는 이유는 단순합니다.

- 어떤 복구 작업이든 etcd 자체가 손상되면 끝
- 스냅샷 한 발이면 최악의 상황에서도 이 시점으로 돌아올 수 있음
- 디스크가 거의 가득 차 있는 상태가 아니면, 만들어 두는 비용이 사실상 무료

이 한 줄을 먼저 박아 두고 진단을 시작했습니다.

---

## 4. 첫 진단 5종 — 10분 안에 보는 것

복구를 시작하기 전에 항상 다음 5종부터 봅니다.
이 5종 안에 보통 원인이 들어 있기 때문입니다.

### 4-1. k3s 로그

가장 결정적인 단서가 들어 있는 곳입니다.

```bash
sudo journalctl -u k3s -n 300 --no-pager | tail -150
```

여기서 보는 키워드들:

- `etcdserver: request timed out`, `slow fdatasync` → 디스크 IO 병목
- `no space left`, `mvcc: database space exceeded` → 디스크/etcd 공간 부족
- `OOMKilled`, `Out of memory: Killed process` → 메모리 부족
- `x509: certificate has expired` → 인증서 만료
- `walpb: crc mismatch`, `corrupt`, `panic` → etcd 데이터 손상

마지막 항목이 보이면 절대 즉흥적으로 복구를 시도하면 안 됩니다.
스냅샷 복구로 가야 하는 분기라, 그 자리에서 멈추고 별도 절차를 잡아야 합니다.

### 4-2. API 헬스 (livez / readyz)

API 서버 입장에서 "지금 살아있느냐 / ready냐"를 직접 묻습니다.

```bash
curl -k -m 5 https://127.0.0.1:6443/livez?verbose
curl -k -m 5 https://127.0.0.1:6443/readyz?verbose
```

해석은 단순합니다.

- 둘 다 응답이 없으면 API 서버 자체가 hung
- `livez`만 OK이고 `readyz`가 fail이면 etcd 또는 일부 컨트롤러만 fail
- 둘 다 OK이면 사실 503이 떨어지지 않아야 합니다

`readyz?verbose`는 줄별로 어떤 컴포넌트가 OK인지 보여주기 때문에,
어디서 막히고 있는지 한 화면에 잡힙니다.

### 4-3. 디스크 / inode

K3s가 떠도 etcd가 못 쓰면 ready가 안 됩니다.
디스크는 두 차원에서 봅니다.

```bash
df -h /var/lib/rancher /var /
df -i /var/lib/rancher /var /
sudo du -sh /var/lib/rancher/k3s/server/db
```

- 용량은 충분한데 inode가 100% 차 있는 경우가 가끔 있습니다.
- `/var/lib/rancher` 가 별도 LV/디스크라면 그것만 따로 볼 것
- etcd DB 폴더가 비정상적으로 크면 STEP 4(공간 확보)로 분기

### 4-4. 메모리 / dmesg

OOM으로 죽었다 다시 떴다 반복하는 상태일 수 있습니다.

```bash
free -h
sudo dmesg -T | tail -80
```

`dmesg`에 `Killed process`가 보이면 OOM 분기.
어떤 프로세스가 죽고 있는지까지 같이 출력되니, k3s/kube-apiserver/etcd 어느 것이 타깃인지 확인할 수 있습니다.

### 4-5. 시간 / 인증서

가끔 가장 어이없는 원인이 여기 있습니다.

```bash
date
sudo openssl x509 -in /var/lib/rancher/k3s/server/tls/serving-kube-apiserver.crt -noout -enddate
sudo openssl x509 -in /var/lib/rancher/k3s/server/tls/server-ca.crt -noout -enddate
```

- `date`가 1970년이거나 한참 어긋나 있으면 RTC/NTP 이슈
- 인증서 enddate가 지난 상태로 부팅됐다면 dynamic-cert 갱신이 막혔을 가능성

폐쇄망에서는 NTP가 없을 수 있어서, 노드 시간이 미세하게 드리프트되다가 갑자기 인증서 검증을 깨뜨리는 경우가 있습니다.

---

## 5. 표준 복구 — 대부분 여기서 끝납니다

위 5종에서 etcd 손상이나 인증서 만료처럼 별도 절차가 필요한 키워드가 안 보였다면,
다음 표준 절차로 거의 끝납니다.

### 5-1. 멈춰 있는 systemd job 정리

```bash
systemctl list-jobs
sudo systemctl cancel <job-id>
```

`k3s.service`의 stop 작업이 남아 있으면 먼저 취소합니다.

### 5-2. 전체 강제 종료

```bash
sudo /usr/local/bin/k3s-killall.sh
sleep 5
```

`k3s-killall.sh`는 K3s가 설치 시 함께 깔아주는 스크립트로,
내부 containerd, mount, CNI 룰, 자식 프로세스까지 한 번에 정리해줍니다.

`systemctl stop`만으로는 정리되지 않는 잔재까지 처리해주는 게 핵심입니다.

### 5-3. 재기동

```bash
sudo systemctl start k3s
```

`restart`가 아니라 `start`입니다.
앞 단계에서 이미 모든 게 내려가 있는 상태라, start 한 번이면 됩니다.

### 5-4. 1~3분 대기 후 확인

```bash
sudo systemctl status k3s --no-pager | head -20
curl -k -m 5 https://127.0.0.1:6443/readyz
kubectl get ns
```

`readyz`의 모든 줄이 `[+]ok` 로 끝나면 정상으로 봐도 됩니다.

대부분의 503 케이스는 이 시점에서 풀립니다.

---

## 6. 어디서 안 풀리면 분기로 가야 하는가

표준 복구로 안 풀린다면, 앞에서 본 5종 진단의 키워드별로 갈 길이 갈립니다.

| 진단에서 본 것 | 가야 하는 방향 |
| --- | --- |
| `mvcc: database space exceeded`, `no space left` | 디스크/etcd 공간 확보 |
| `OOMKilled` | 메모리 회수 또는 워크로드 scale-down |
| `x509: certificate has expired` | `dynamic-cert.json` 백업 후 재발급 |
| `date`가 한참 어긋남 | 수동 시간 설정 + `hwclock --systohc` |
| `walpb: crc mismatch`, `corrupt` | etcd 스냅샷 복구 (위험 절차) |
| iptables/CNI 룰 누락 | k3s 재기동으로 룰 재배포 |

이 글에서는 표준 복구까지만 다뤘고,
각 분기는 시나리오가 충분히 달라서 별도 글로 풀어내는 편이 깔끔하다고 느꼈습니다.

특히 `corrupt`/`crc mismatch` 키워드가 보였을 때는,
표준 복구로 살리려는 시도 자체가 데이터 손상을 더 키울 수 있어서 그 시점에 멈춰야 합니다.

---

## 7. 짚어두고 싶은 것들

### 7-1. `systemctl restart`는 hang에 가장 취약한 명령

K3s가 이미 ready가 아닌 상태에서 `restart`를 치면,
stop 단계에서 그대로 멈추는 경우가 많습니다.

이 한 명령이 막히면 그 위에서 다른 systemd 명령들도 따라 막히기 때문에,
"restart 한 번"이 의외로 디버깅을 어렵게 만드는 첫 단추가 되기도 합니다.

비정상 상태일 때의 표준은 항상 다음 순서였습니다.

```text
k3s-killall.sh → systemctl start k3s
```

### 7-2. 손대기 전 etcd snapshot은 거의 무료다

`k3s etcd-snapshot save` 한 번은 보통 몇 초도 걸리지 않고 디스크도 크게 잡지 않습니다.
그런데 만약 복구 도중 etcd가 더 깨졌을 때, 이 한 발이 모든 차이를 만듭니다.

> 위험을 안 보고 빠르게 가는 것보다,
> 위험을 한 번 줄여 두고 평소 속도로 가는 게 결과적으로 더 빠르다.

### 7-3. 5종 진단의 순서가 곧 분기표

`journalctl` → `livez/readyz` → `df/du` → `free/dmesg` → `date/openssl` 다섯 번의 명령이면
대부분의 K3s 503 케이스가 어떤 분기로 가야 하는지 결정됩니다.

이 순서를 외워두고 시작하면, 같은 상황을 다음에 봐도 10분 안에 진단이 끝납니다.

### 7-4. 12분이 지나도 진척이 없으면 재설치 절차로 넘긴다

이 부분은 운영하면서 따로 정해 둔 기준입니다.

- 표준 복구로 안 되고
- 분기표에서도 명확한 키워드가 안 잡히고
- 디스크/메모리/인증서가 모두 정상으로 보이는데도 API가 안 살아나면

이 시점부터는 더 깊이 파보는 시간보다 재설치 절차의 비용이 더 작아집니다.
백업해 둔 etcd 스냅샷과 PVC 데이터만 있으면 재설치는 보통 수십 분 안에 끝납니다.

이 임계점을 미리 정해두지 않으면, 1시간이 2시간이 되고 3시간이 되어버립니다.

---

## 8. 마무리

처음 503을 봤을 때는 솔직히 머릿속이 좀 멍해졌습니다.

> kubectl이 안 먹힌다. systemctl restart도 막혔다.
> 그러면 무엇부터 봐야 하지?

이 글의 5종 진단과 표준 복구 절차는,
같은 상황을 다음에 또 만나도 비슷한 속도로 풀 수 있도록 평소 다니던 길을 짧게 정리한 것입니다.

K3s는 단일 바이너리 안에 여러 컴포넌트가 묶여 있는 구조라서,
정상일 때는 가장 단순한 분산 K8s지만 비정상일 때는 어디가 문제인지 가리기가 까다롭습니다.

그래서 더더욱, 처음 보는 5종 명령 / 손대기 전 스냅샷 / `killall → start` 의 표준 절차가
운영 기준으로 자리 잡아 있어야 한다고 느꼈습니다.
