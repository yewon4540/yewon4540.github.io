---
title: k3s 클러스터 기본 세팅
layout: default
parent: k3s
grand_parent: Kubernetes
nav_order: 1
written_at: 2026-03-27
---

# k3s 클러스터 기본 세팅

k3s 클러스터를 새로 구성할 때 진행하는 기본 세팅 절차를 정리합니다.

---

## 사전 체크리스트

- Private 망 여부 확인
- 볼륨 마운트 구성 계획 확인
- 방화벽 포트 오픈 여부 확인

---

## 1. Hosts 설정

```bash
sudo vi /etc/hosts
# <IP> <hostname> 형식으로 추가
```

---

## 2. k3s Server 설치

### 2-1) 볼륨 마운트 경로 사전 구성

기본 경로 대신 별도 디렉토리를 사용할 경우 설치 전에 먼저 생성합니다.

```bash
sudo mkdir -p /sw/k3s/agent
sudo mkdir -p /containerd
sudo mkdir -p /etc/rancher/k3s
```

config 파일로 설정하는 방법:

```bash
sudo vi /etc/rancher/k3s/config.yaml
```

```yaml
data-dir: /sw/k3s
kubelet-arg:
  - "root-dir=/sw/k3s/agent/kubelet"
```

### 2-2) 설치 명령어

```bash
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_SKIP_SELINUX_RPM=true \
  INSTALL_K3S_EXEC='server \
    --write-kubeconfig-mode=644 \
    --disable=traefik \
    --data-dir=/sw/k3s \
    --kubelet-arg=root-dir=/sw/kubelet \
    --tls-san=<SERVER_IP>' sh -
```

주요 옵션 설명:

- `server`: control-plane 노드로 실행
- `--write-kubeconfig-mode=644`: kubeconfig 파일을 일반 사용자도 읽을 수 있도록 권한 설정
- `--disable=traefik`: 기본 Ingress Controller 비활성화 (Istio 사용 전제)
- `--data-dir`: 데이터 저장 경로 변경
- `--tls-san`: 클러스터 접근에 사용할 IP/도메인 추가

### 2-3) 설치 상태 확인

```bash
systemctl status k3s --no-pager
kubectl get nodes -o wide
kubectl get pods -A
```

---

## 3. Worker Node 연결

### 3-1) Join Token 확인 (마스터 노드에서)

```bash
cat /var/lib/rancher/k3s/server/node-token
```

### 3-2) Worker Node Join

기본 환경:

```bash
curl -sfL https://get.k3s.io | \
  K3S_URL=https://<SERVER_IP>:6443 \
  K3S_TOKEN=<NODE_TOKEN> sh -
```

Private 망 환경:

```bash
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_SKIP_SELINUX_RPM=true \
  INSTALL_K3S_TYPE=agent \
  K3S_URL=https://<SERVER_IP>:6443 \
  K3S_TOKEN=<NODE_TOKEN> sh -
```

---

## 4. NodeHosts 설정

DB 서버 등 내부 호스트를 클러스터 내에서 이름으로 접근해야 할 경우 아래처럼 설정합니다.

### 4-1) 마스터 노드 (CoreDNS 수정)

```bash
kubectl -n kube-system edit configmap coredns
```

`data.NodeHosts` 블록 아래에 추가:

```text
<DB_HOST_IP> k3s-host
```

### 4-2) 워커 노드 (`/etc/hosts` 수정)

```bash
sudo vi /etc/hosts
# <HOST_IP> k3s-host 추가

sudo systemctl restart k3s-agent
```

---

## 5. Private Registry 설정 (Insecure)

Private Registry를 HTTP 또는 자체 서명 인증서로 운영할 경우 아래처럼 설정합니다.

### 5-1) Docker

```bash
sudo vi /etc/docker/daemon.json
```

```json
{
  "insecure-registries": ["<REGISTRY_HOST>:<PORT>"]
}
```

```bash
sudo systemctl restart docker.service
```

### 5-2) k3s

```bash
sudo vi /etc/rancher/k3s/registries.yaml
```

```yaml
mirrors:
  "<REGISTRY_HOST>:<PORT>":
    endpoint:
      - "http://<REGISTRY_HOST>:<PORT>"

configs:
  "<REGISTRY_HOST>:<PORT>":
    auth:
      username: <REGISTRY_USER>
      password: <REGISTRY_PASSWORD>
    tls:
      insecure_skip_verify: true
```

### 5-3) k3d

```bash
docker exec -it <k3d_container> vi /etc/rancher/k3s/registries.yaml
```

내용은 k3s 설정과 동일한 형식으로 작성합니다.

---

## 6. 이하 마스터 노드에서만 진행

### 6-1) MetalLB 설치

LoadBalancer 타입 서비스를 클러스터 내에서 사용하기 위한 로드밸런서입니다.

```bash
kubectl create ns metallb-system
helm repo add metallb https://metallb.github.io/metallb
helm repo update
helm install metallb metallb/metallb --version 0.15.2 -n metallb-system \
  --set controller.securityContext.allowPrivilegeEscalation=false \
  --set speaker.securityContext.allowPrivilegeEscalation=false \
  --set speaker.hostNetwork=true \
  --set speaker.tolerateMaster=true \
  --set prometheus.metricsPort=7472

kubectl apply -f address-pool.yaml
kubectl get pods -A
kubectl get svc -A
```

### 6-2) Istio 설치

```bash
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.27.3 sh -
cd istio-1.27.3
export PATH=$PWD/bin:$PATH
istioctl install --set profile=default -y
```

앱 네임스페이스 생성 및 sidecar 자동 주입 설정:

```bash
kubectl create ns apps
kubectl label ns apps istio-injection=enabled
```

### 6-3) ArgoCD 설치

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl apply -f argocd-gateway.yaml
kubectl apply -f argocd-vs.yaml
```

초기 admin 비밀번호 확인:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```
