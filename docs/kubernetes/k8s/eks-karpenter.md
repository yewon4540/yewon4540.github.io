---
title: Karpenter 기반 EKS 자동 스케일링 구성 (트래픽 급증 대응)
layout: default
parent: k8s
grand_parent: Kubernetes
nav_order: 4
written_at: 2026-03-31
---

# Karpenter 기반 EKS 자동 스케일링 구성 (트래픽 급증 대응)

쇼핑몰 서비스 운영 중 트래픽 급증 상황에 대응하기 위해,
EKS 환경에서 Karpenter 기반 자동 스케일링 구조를 구성한 내용을 정리한다.

---

## 문제/상황

트래픽이 특정 시점에 급격히 증가하는 구간이 반복적으로 발생했다.

- 프로모션 기간(예측 가능)
- 외부 이슈/입소문 유입(예측 불가)

기존 운영 방식의 한계는 다음과 같았다.

- 노드를 크게 고정하면 평시 비용이 증가
- 노드를 작게 고정하면 급증 시 Pending Pod 및 응답 지연 발생
- 수동 증설은 대응 지연 가능성이 높음

즉, 예측 가능한 이벤트와 예측 불가능한 이벤트를 모두 흡수할 수 있는 자동 확장 구조가 필요했다.

---

## 해결 방법 / 개요

Karpenter를 통해 워크로드 기반 자동 스케일링을 구성했다.

구성 요소:

- Karpenter Controller
- `EC2NodeClass`
- `NodePool`
- 부하 유발용 Deployment

핵심은 Pod의 리소스 요청량을 기준으로 필요한 노드를 즉시 생성하고,
유휴 노드는 자동 정리하도록 정책을 설정하는 것이다.

---

## 동작 흐름

```text
[Pod Pending 발생]
  ↓
[Karpenter NodeClaim 생성]
  ↓
[EC2 Instance 생성]
  ↓
[Node Join → Pod Scheduling]
  ↓
[유휴 상태 시 자동 축소]
```

---

## 사전 준비

- EKS 클러스터 구성 완료
- Karpenter Controller 설치 완료
- IAM Role 준비
  - Controller용 IAM Role
  - Node용 IAM Role
- Subnet / Security Group에 discovery 태그 적용

---

## 1) Node 스펙 정의 (`EC2NodeClass`)

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiFamily: AL2023
  amiSelectorTerms:
    - alias: al2023@latest

  role: KarpenterNodeRole-<cluster-name>

  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: sample-eks-cluster

  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: sample-eks-cluster
```

설정 포인트:

- `amiSelectorTerms.alias`로 관리형 AMI 추적
- `role`은 Worker Node에 부여할 IAM Role
- `subnetSelectorTerms`/`securityGroupSelectorTerms`는 태그 기반 검색

---

## 2) 스케일 정책 정의 (`NodePool`)

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default

      requirements:
        - key: node.kubernetes.io/instance-type
          operator: In
          values: ["m5.2xlarge"]

        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]

      expireAfter: 604800s

  limits:
    cpu: 160

  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 30s
    budgets:
      - nodes: 10%
```

주요 설정:

- 인스턴스 타입 제한 (`requirements`)
- 최대 확장 상한 (`limits.cpu`)
- 자동 축소 정책 (`consolidationPolicy`, `consolidateAfter`)
- 노드 수명 주기 관리 (`expireAfter`)

---

## 3) 부하 테스트 및 동작 확인

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: stress-test
spec:
  replicas: 4
  selector:
    matchLabels:
      app: stress-test
  template:
    metadata:
      labels:
        app: stress-test
    spec:
      containers:
        - name: stress
          image: public.ecr.aws/eks-distro/kubernetes/pause:3.2
          resources:
            requests:
              cpu: "4"
              memory: "2Gi"
```

확인 순서:

1. Pod Pending 발생
2. `NodeClaim` 생성 확인
3. EC2 인스턴스 생성 확인
4. Node Ready 이후 Pod 스케줄링 확인

추가로 inflate 방식으로 요청량을 단계적으로 늘려,
점진 확장 동작도 함께 검증했다.

---

## 4) 적용 시 확인 포인트 / 트러블슈팅

### 4-1) 노드가 생성되지 않는 경우

- `EC2NodeClass`의 Subnet/SG 태그 매칭 여부 확인
- Node IAM Role 권한(EC2, ECR, CNI 관련) 확인
- `NodePool requirements`가 과도하게 좁지 않은지 확인

### 4-2) 확장은 되지만 축소가 느린 경우

- `disruption.consolidateAfter` 값 재조정
- `budgets.nodes` 값이 너무 보수적인지 확인
- 실제 워크로드가 요청 리소스를 과하게 잡고 있는지 점검

### 4-3) 비용이 예상보다 큰 경우

- `limits.cpu` 상한 재점검
- `on-demand`만 사용 중이면 Spot 혼합 전략 검토
- 기본 리소스 요청값(requests) 과다 설정 여부 점검

---

## 결과

- 트래픽 증가 시 노드 자동 생성 동작 확인
- 증설 후 Pod가 정상 스케줄링되어 서비스 지속성 확보
- 유휴 시 자동 축소로 불필요 노드 제거

정리하면 다음과 같다.

- 성능: 급증 트래픽 구간에서도 안정적 처리
- 비용: 유휴 리소스 자동 정리로 비용 절감
- 운영: 수동 개입 최소화

---

## 참고

- Karpenter는 Pod의 `requests`를 기준으로 노드 용량을 계산한다.
- Managed Node Group과 병행 시 기본 노드/동적 노드 역할을 분리하는 것이 좋다.
- 자동 축소 정책은 서비스 특성과 배포 패턴에 맞춰 점진적으로 튜닝해야 한다.
