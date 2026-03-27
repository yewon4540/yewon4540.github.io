---
title: Kubernetes 환경에서 Jenkins 구축 및 트러블슈팅 정리
layout: default
parent: Jenkins
grand_parent: Devops
nav_order: 2
written_at: 2026-03-27
---

# Kubernetes 환경에서 Jenkins 구축 및 트러블슈팅 정리

Kubernetes 환경에서 Jenkins를 구축하면서 겪은 문제와 해결 과정을 정리합니다.
단순 설치보다 운영 중 실제로 발생한 트러블 대응에 초점을 맞췄습니다.

---

## 문제/상황

기존에는 Jenkins를 Docker 기반으로 운영하거나 VM/EC2에 직접 설치하는 방식이 일반적이었습니다.

하지만 다음과 같은 문제가 있었습니다.

- Jenkins 서버 단일 장애 지점(SPOF)
- 컨테이너 기반 서비스와 분리된 운영 환경
- 인프라 구성과 CI/CD 환경의 불일치
- 스케일링 및 운영 자동화 한계

Kubernetes 기반 서비스 환경에서 Jenkins만 별도로 운영하는 구조는 점점 비효율적이었습니다.

---

## 해결 방법 / 개요

Kubernetes 위에 Jenkins를 StatefulSet으로 구성하고, 아래 구조를 적용했습니다.

- Jenkins를 Kubernetes 내부에서 실행
- PVC로 Jenkins 데이터 영속성 확보
- `docker.sock` mount 방식으로 Docker build 수행
- Helm chart 기반 배포/관리

---

## 아키텍처 / 흐름

### 1) 전체 구조

```mermaid
flowchart LR
    A[Developer] --> B[Git Repository]
    B --> C[Jenkins (Kubernetes Pod)]
    C --> D[docker.sock]
    D --> E[Node Docker Daemon]
    E --> F[Docker Image Build]
    F --> G[Private Registry]
```

### 2) Kubernetes 내부 구조

```mermaid
flowchart TD
    subgraph Kubernetes
        J[Jenkins Pod]
        I[Init Container]
        P[PVC (/var/jenkins_home)]
        S[docker.sock]
    end

    J --> P
    J --> S
    I --> P
    S --> D[Node Docker]
```

---

## 사전 준비

- Kubernetes 클러스터
- Helm
- Jenkins Helm chart
- PersistentVolumeClaim(PVC)
- Docker가 설치된 노드

---

## 1. Jenkins를 Kubernetes에 배포

Jenkins는 Helm chart를 사용해 StatefulSet 형태로 배포했습니다.

```bash
helm install jenkins jenkins/jenkins -n jenkins
```

StatefulSet을 사용한 이유:

- Jenkins는 상태를 가지는 서비스(예: jobs, credentials)
- Pod 재시작 시 데이터 유지 필요
- PVC 기반 운영이 필요

### 1-1) Docker build를 위한 설정

```yaml
volumeMounts:
  - mountPath: /var/run/docker.sock
    name: docker-socket
```

### 1-2) 권한 설정

```yaml
securityContext:
  runAsUser: 0
```

---

## 2. 트러블슈팅 과정

### 2-1) Plugin 설치 실패

- 원인: `plugins.txt`에서 `latest` 사용
- 결과: init container `CrashLoopBackOff`
- 해결: `plugins.txt` 제거 또는 최소화, 버전 고정

### 2-2) Read-only filesystem 문제

증상:

```text
/root/.cache: Read-only file system
```

원인:

- `readOnlyRootFilesystem: true`

해결:

```yaml
readOnlyRootFilesystem: false
```

또는

```yaml
env:
  - name: HOME
    value: /tmp
```

### 2-3) Docker build 실패

증상:

```text
ERROR: mkdir /root/.docker: read-only file system
```

원인:

- Docker CLI가 `/root/.docker`에 쓰기 시도

해결:

- `readOnlyRootFilesystem` 비활성화 또는 쓰기 가능한 경로 지정

### 2-4) Docker 권한 문제

증상:

```text
permission denied while trying to connect to the Docker daemon socket
```

원인:

- `docker.sock` 접근 권한 부족

해결:

```yaml
securityContext:
  runAsUser: 0
```

### 2-5) Git checkout 실패

증상:

```text
fatal: not in a git directory
```

원인:

- Jenkins workspace 손상

해결:

```bash
rm -rf /var/jenkins_home/workspace/*
```

---

## 3. 운영 시 한계와 고려사항

### 3-1) `docker.sock` 방식

- 노드 Docker daemon에 직접 접근하는 방식이라 권한 범위가 큼
- 운영 보안 정책에 따라 별도 대안 검토 필요

### 3-2) `readOnlyRootFilesystem` 비활성화

- 안정적 빌드를 위해 비활성화했지만 보안 기준과 충돌 가능
- 이미지/워크스페이스 경로 설계를 함께 고려해야 함

### 3-3) Plugin 관리

- 자동 설치를 줄이면 버전 안정성은 높아지지만 관리 부담 증가

---

## 정리

Kubernetes에서 Jenkins를 운영할 때 핵심은 아래 3가지입니다.

- 상태 데이터(PVC) 유지
- 빌드 환경 권한(`docker.sock`, securityContext) 정합성
- Plugin/Workspace 운영 정책 관리

초기 구성보다 운영 중 트러블 대응 기준을 먼저 정해두는 것이 실제 안정성에 더 도움이 됩니다.

---

## 참고

- Jenkins Helm Chart 문서
- Kubernetes StatefulSet 문서
- Jenkins Plugin 관리 가이드
