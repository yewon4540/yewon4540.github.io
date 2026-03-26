---
title: Kubernetes 환경에서 Jenkins 구축 및 트러블슈팅 정리
layout: default
parent: CI/CD
grand_parent: DevOps
nav_order: 1
written_at: 2026-03-26
---

# Kubernetes 환경에서 Jenkins 구축 및 트러블슈팅 정리

Kubernetes 환경에서 Jenkins를 구축하면서 겪은 문제와 해결 과정을 정리합니다.  
단순 설치가 아니라 실제 운영 중 발생한 트러블과 대응 과정을 중심으로 기록합니다.

---

## 문제/상황

기존에는 Jenkins를 Docker 기반으로 운영하거나 EC2에 직접 설치하는 방식이 일반적이었습니다.  

하지만 다음과 같은 문제가 있었습니다.

- Jenkins 서버 단일 장애 지점 (SPOF)
- 컨테이너 기반 서비스와의 분리된 환경
- 인프라 구성과 CI/CD 환경이 분리됨
- 스케일링 및 운영 자동화의 한계

특히 Kubernetes 기반으로 서비스가 운영되는 상황에서, Jenkins만 별도로 운영하는 구조는 점점 비효율적으로 느껴졌습니다.

---

## 해결 방법 / 개요

Kubernetes 위에 Jenkins를 StatefulSet으로 구성하고, 다음과 같은 구조를 적용했습니다.

- Jenkins를 Kubernetes 내부에서 실행
- PVC를 통해 데이터 영속성 확보
- docker.sock mount 방식으로 Docker build 수행
- Helm chart 기반으로 Jenkins 배포 및 관리

---

## 아키텍처 / 흐름

### 1) 전체 구조

```mermaid
flowchart LR
    A[Developer] --> B[GitLab Repository]
    B --> C[Jenkins (Kubernetes Pod)]
    C --> D[docker.sock]
    D --> E[Node Docker Daemon]
    E --> F[Docker Image Build]
    F --> G[Private Registry]
```

---

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
- Jenkins Helm Chart
- PersistentVolumeClaim (PVC)
- Docker가 설치된 노드

---

## 1. Jenkins를 Kubernetes에 배포

Jenkins는 Helm Chart를 사용하여 StatefulSet 형태로 배포했습니다.

```bash
helm install jenkins jenkins/jenkins -n jenkins
```

StatefulSet을 사용하는 이유는 다음과 같습니다.

- Jenkins는 상태를 가지는 서비스 (jobs, credentials 등)
- Pod 재시작 시 데이터 유지 필요
- PVC 기반으로 안정적인 운영 가능

---

### 1-1) docker build를 위한 설정

```yaml
volumeMounts:
  - mountPath: /var/run/docker.sock
    name: docker-socket
```

---

### 1-2) 권한 설정

```yaml
securityContext:
  runAsUser: 0
```

---

## 2. 트러블슈팅 과정

### 2-1) plugin 설치 실패

- 원인: plugins.txt에서 latest 사용
- 결과: init container CrashLoopBackOff
- 해결: plugins.txt 제거 또는 최소화

---

### 2-2) read-only filesystem 문제

- 증상:
```
/root/.cache: Read-only file system
```

- 원인: readOnlyRootFilesystem: true
- 해결:
```yaml
readOnlyRootFilesystem: false
```

또는

```yaml
env:
  - name: HOME
    value: /tmp
```

---

### 2-3) docker build 실패

- 증상:
```
ERROR: mkdir /root/.docker: read-only file system
```

- 원인: Docker CLI가 /root/.docker에 쓰기 시도
- 해결: readOnlyRootFilesystem 비활성화

---

### 2-4) docker 권한 문제

- 증상:
```
permission denied while trying to connect to the Docker daemon socket
```

- 원인: docker.sock 접근 권한 없음
- 해결:
```yaml
securityContext:
  runAsUser: 0
```

---

### 2-5) Git checkout 실패

- 증상:
```
fatal: not in a git directory
```

- 원인: workspace 손상
- 해결:
```bash
rm -rf /var/jenkins_home/workspace/*
```

---

## 3. 트러블슈팅의 한계

### 3-1) docker.sock 방식

- Jenkins가 host root 권한과 동일한 수준의 권한을 가짐
- 보안적으로 취약

---

### 3-2) readOnlyRootFilesystem 비활성화

- 보안을 위해 필요한 설정이지만 비활성화 상태

---

### 3-3) plugin 관리

- 자동 설치 제거 → 수동 관리 필요

---

## 참고

- StatefulSet은 Jenkins 같은 상태 기반 서비스에 적합
- workspace는 캐시 영역이라 초기화 가능
