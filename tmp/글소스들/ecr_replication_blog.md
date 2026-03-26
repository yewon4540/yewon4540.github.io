---
title: AWS ECR Cross Account 이미지 미러링 구성 및 트러블슈팅
layout: default
parent: Container
grand_parent: Cloud
nav_order: 1
written_at: 2026-03-26
---

# AWS ECR Cross Account 이미지 미러링 구성 및 트러블슈팅

CI/CD 과정에서 빌드된 이미지를 다른 AWS 계정으로 전달하기 위해  
ECR Cross Account Replication을 구성하며 겪은 과정과 주의사항을 정리합니다.

---

## 문제/상황

기존 구조에서는 빌드된 Docker 이미지를 직접 전달하거나,  
대상 계정에서 외부 ECR을 pull하는 방식으로 배포가 이루어졌습니다.

이 방식에는 다음과 같은 문제가 있었습니다.

- 배포 시 외부 네트워크 의존성 발생
- 이미지 전달 과정이 수동 또는 복잡
- 배포 시간이 길어짐

특히 특정 고객사 환경에서는 내부 계정에서만 이미지를 사용하는 구조가 필요했습니다.

---

## 해결 방법 / 개요

AWS ECR의 replication 기능을 사용하여  
이미지를 자동으로 다른 계정으로 복제하는 구조를 구성했습니다.

구성 요소:

- Source 계정 ECR (이미지 push)
- Destination 계정 ECR (이미지 수신)
- Cross Account Replication rule
- Registry Permission 설정

---

## 아키텍처 / 흐름

```
[CI/CD] → [Plateer ECR] → [Replication] → [Lotte ECR] → [Deploy]
```

---

## 사전 준비

- 두 AWS 계정 존재 (Source / Destination)
- 동일 리전 (예: ap-northeast-2)
- ECR 사용 가능 상태
- 대상 계정에 registry permission 설정 가능

---

## 1. Source 계정(ECR) Replication Rule 설정

```yaml
rules:
  - destinations:
      - region: ap-northeast-2
        registryId: 730335615047
    repositoryFilters:
      - filter: xgen/xgen-registry
        filterType: PREFIX_MATCH
```

설명

- 특정 prefix (`xgen/xgen-registry`)를 가진 repository만 복제
- 대상 계정 registryId 지정
- 동일 rule로 여러 계정에 동시에 복제 가능

### 1-1) Repository Filter

```yaml
filter: xgen/xgen-registry
```

이 설정을 통해 다음과 같은 repository만 복제됩니다.

```
xgen/xgen-registry/xgen-front
xgen/xgen-registry/xgen-back
```

### 1-2) Multi Account Replication

하나의 rule에서 여러 destination을 설정할 수 있습니다.

```yaml
destinations:
  - registryId: A
  - registryId: B
```

---

## 2. Destination 계정 Registry Permission 설정

Replication을 위해서는 destination 계정에서  
Source 계정에 대한 권한을 허용해야 합니다.

```json
{
  "Sid": "copy_registry",
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::318919594903:root"
  },
  "Action": [
    "ecr:CreateRepository",
    "ecr:ReplicateImage"
  ],
  "Resource": "arn:aws:ecr:ap-northeast-2:730335615047:repository/xgen/xgen-registry/*"
}
```

설명

- Source 계정이 repository 생성 및 이미지 복제를 수행할 수 있도록 허용
- 특정 prefix에 대해서만 권한 부여 (보안 목적)

---

## 3. 이미지 Push 및 복제 확인

```bash
docker push xgen/xgen-registry/xgen-front:test
```

설명

- Replication rule 생성 이후 push된 이미지부터 복제됨
- 새로운 tag로 push하여 테스트 필요

---

## 참고

### 1. Replication은 기존 이미지에 적용되지 않음

- rule 생성 이전 이미지 → 복제되지 않음
- 반드시 신규 push 필요

---

### 2. Repository prefix 구조 중요

```
xgen/xgen-registry/*
```

prefix가 다르면 replication 대상에서 제외됩니다.

---

### 3. Registry Permission 위치

```
ECR → Private registry → Permissions
```

- Repository policy가 아님
- Registry permission에 설정해야 정상 동작

---

### 4. Resource ARN 범위

```
repository/xgen/xgen-registry/*
```

- 특정 repository prefix만 허용 가능
- 불필요한 repository 복제 방지

---

### 5. 가장 많이 발생하는 문제 (실제 케이스)

- Account ID 오기입

```
750335615047 (오기입)
730335615047 (정상)
```

Replication rule 자체는 정상이어도  
destination account ID가 틀리면 복제가 수행되지 않습니다.

---

## 정리

| 항목 | 내용 |
| --- | --- |
| 핵심 기능 | ECR Cross Account Replication |
| 목적 | 이미지 자동 복제 |
| 주요 구성 | Replication Rule + Registry Permission |
| 필터링 | Repository Prefix 기반 |
| 주의사항 | Account ID, 신규 push, 권한 위치 |

ECR replication을 사용하면  
CI/CD와 배포 구조를 단순화하고, 계정 간 이미지 전달을 자동화할 수 있습니다.
