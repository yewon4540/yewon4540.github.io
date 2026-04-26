---
title: 포트폴리오
layout: default
parent: 커리어&포트폴리오
nav_order: 1
written_at: 2026-04-27
---

# 박예원 포트폴리오

## 1. Profile

Cloud / DevOps / Kubernetes 기반으로 배포 구조, 운영 자동화, 인프라 전달 체계를 개선해온 엔지니어 박예원입니다.

AWS 운영, Jenkins/GitLab/Nexus 기반 CI/CD, Helm/Kubernetes 배포 구조, Terraform 기반 프로비저닝 자동화, 폐쇄망 환경의 이미지 전달 구조 개선 경험을 보유하고 있습니다. 단순히 리소스를 구성하는 것보다, 고객사 환경 제약과 운영 조건을 고려해 실제로 반복 가능하고 안정적으로 운영될 수 있는 구조를 만드는 데 관심을 두고 일해왔습니다.

대표적으로 금융권 폐쇄망 환경에서 LLMOps 서비스(XGEN)의 air-gap 설치 구조와 이미지 전달 패키징 방식을 정리하고, ECR Mirroring 및 로컬 Registry 연계 구조를 구성한 경험이 있습니다. 또한 롯데홈쇼핑 프로젝트에서는 배포 전달 절차를 개선해 설치·배포 단계를 8단계에서 2단계로 줄였고, Jenkins, GitLab, Nexus, Registry 기반 CI/CD 구조를 운영하며 Helm 기반 공통 템플릿과 환경별 배포 설정을 정리해 프로젝트별 배포 방식을 표준화했습니다.

---

## 2. Core Positioning

### Cloud & DevOps Architecture
- AWS 기반 인프라 운영, 비용·권한·보안 이슈 검토
- ECR, Registry, CloudFront, ALB, Route53 등 서비스 전달 구조 검토
- 고객사 환경 제약에 맞춘 배포·설치 구조 설계 및 운영 방식 정리
- Public Cloud 환경에서 반복 가능한 구축·배포 절차를 만들기 위한 자동화 경험

### Kubernetes / Container Platform
- Kubernetes 및 Docker 기반 서비스 배포 구조 구성
- Helm 기반 공통 템플릿 및 환경별 배포 설정 정리
- Blue-Green, Canary 배포 흐름 적용 경험
- EKS, Karpenter, Probe, Istio 등 Kubernetes 운영 요소에 대한 기술 검증 및 블로그 정리

### CI/CD & Automation
- Jenkins, GitLab, Nexus, Registry 기반 CI/CD 구조 운영
- Jenkinsfile, Groovy, properties 기반 배포 흐름 구성
- Terraform 기반 리소스 요청/프로비저닝 자동화 경험
- 반복 배포·점검·인증서 작업의 자동화 구조 검토

### Observability / Operation
- CloudWatch 기반 모니터링 및 알림 구성 경험
- Fluentd + OpenSearch 로그 수집 구조 검증
- Uptime Kuma Kubernetes 운영 및 DB 마이그레이션 구조 정리
- 장애 원인 추적, 로그 확인, 운영 문서화 경험

---

## 3. Representative Projects

### 3-1. 금융권 폐쇄망 LLMOps 서비스(XGEN) 구축·배포·운영

**배경**  
금융권 폐쇄망 환경에서는 외부 네트워크 접근이 제한되어 컨테이너 이미지와 배포 산출물을 일반적인 방식으로 직접 가져오기 어렵습니다. XGEN은 Python/GPU 기반 서비스 특성과 LLMOps 구성요소를 포함하고 있어, 기존 배포 흐름을 그대로 적용하기보다 폐쇄망 환경에 맞는 설치·전달 구조가 필요했습니다.

**수행 내용**
- 금융권 폐쇄망 환경의 외부망 접근 제한 조건을 고려한 air-gap 설치 구조 검토
- XGEN 서비스 설치를 위한 이미지 전달 패키징 방식 정리
- ECR Mirroring 및 로컬 Registry 연계 방식 구성
- 컨테이너 이미지 반입, 태깅, 전달 절차를 재현 가능한 형태로 정리
- 신규 Python/GPU 기반 서비스 구조에 맞춘 CI/CD 파이프라인 구성
- Kubernetes 기반 서비스 배포 및 운영 구조 구성

**성과**
- 폐쇄망 환경에서 반복 가능한 이미지 전달 및 배포 절차 확보
- 고객사 보안·운영 제약을 고려한 LLMOps 서비스 설치 기반 마련
- 외부망 접근이 제한된 환경에서도 서비스 구축·배포·운영이 가능하도록 전달 구조 표준화

**사용 기술**  
`Kubernetes` `Docker` `AWS ECR` `Local Registry` `Jenkins` `GitLab` `Nexus` `CI/CD` `LLMOps`

---

### 3-2. 롯데홈쇼핑 프로젝트 배포 전달 절차 개선

**배경**  
고객사 환경에서 서비스 설치·배포 과정이 여러 단계로 나뉘어 있었고, 이미지 전달 및 배포 절차에 수작업 의존도가 높았습니다. 배포 절차가 복잡할수록 작업자의 실수 가능성이 높아지고, 동일한 절차를 반복하기 어려운 문제가 있었습니다.

**수행 내용**
- 컨테이너 이미지 전달 및 배포 절차의 병목 구간 확인
- ECR Mirroring 및 Registry 연계 방식을 활용한 이미지 전달 구조 개선
- 설치·배포 과정에서 반복 수행되던 단계를 정리하고 단순화
- 배포자가 동일한 기준으로 작업할 수 있도록 전달 절차와 실행 흐름 정리

**성과**
- 설치·배포 단계를 8단계에서 2단계로 축소
- 배포 절차의 수작업 의존도와 반복 작업 부담 감소
- 고객사 환경에서 재현 가능한 배포 전달 구조 확보

**사용 기술**  
`Docker` `Registry` `AWS ECR` `CI/CD` `Jenkins` `GitLab`

---

### 3-3. Jenkins/GitLab/Nexus 기반 CI/CD 표준화

**배경**  
프로젝트별로 CI/CD 구조가 분산되어 있고, 배포 설정과 환경 변수가 개별적으로 관리되어 유지보수 부담이 있었습니다. 일부 배포는 운영자 의존도가 높아 신규 프로젝트나 환경 추가 시 반복 작업이 발생했습니다.

**수행 내용**
- Jenkins, GitLab, Nexus, Registry 기반 CI/CD 구조 운영
- Jenkinsfile, Groovy, properties 기반 배포 흐름 구성
- Helm 기반 공통 템플릿 구조를 활용한 배포 설정 표준화
- 환경별 변수 관리 및 프로젝트별 배포 분기 구조 정리
- Docker 이미지 빌드, Registry 업로드, 배포 실행 흐름 문서화
- Kubernetes 및 Docker 환경에서 Blue-Green, Canary 배포 흐름 적용

**성과**
- 프로젝트별 배포 구조의 중복 구성 감소
- Helm 기반 공통 템플릿을 통해 배포 설정 재사용성 향상
- Node.js 기반 서비스 배포 시간을 약 30분에서 약 10분 내외로 단축한 사례 보유
- 운영자 의존도가 높은 배포 흐름을 표준화된 절차로 정리

**사용 기술**  
`Jenkins` `GitLab` `Nexus` `Docker` `Helm` `Kubernetes` `Groovy` `CI/CD`

---

### 3-4. AWS 운영 및 Terraform 기반 프로비저닝 자동화

**배경**  
교육 및 내부 운영 환경에서 AWS 리소스 요청이 반복적으로 발생했고, 관리자 수동 개입과 계정별 접근 방식의 차이로 인해 운영 효율이 떨어지는 문제가 있었습니다.

**수행 내용**
- EC2, RDS, S3, IAM, CloudWatch 기반 AWS 운영
- 과정별로 분리된 AWS 계정 접근 방식을 IAM Role 기반 구조로 정리
- CloudWatch 경보를 활용한 보안그룹 오설정 및 액세스키 유출 이슈 대응
- Terraform 기반 리소스 요청/프로비저닝 자동화 구조 구성
- RDS 제거, 설치형 DB 전환, EC2 통합, 일부 온프레미스 전환 검토 및 적용

**성과**
- 월 AWS 비용을 3,000달러 이상에서 1,500달러 미만 수준으로 절감
- 반복적인 리소스 생성 요청의 수동 처리 부담 감소
- 인프라 생성 방식의 일관성 및 운영 편의성 개선
- 계정 접근 방식과 리소스 생성 절차를 표준화해 운영 관리 부담 완화

**사용 기술**  
`AWS` `EC2` `RDS` `S3` `IAM` `CloudWatch` `Terraform` `Linux`

---

### 3-5. EKS/Kubernetes 운영 안정화 기술 검증

**목적**  
Kubernetes 기반 서비스 운영에서 트래픽 증가, Rollout 안정성, Pod 상태 제어, 노드 확장 정책을 이해하기 위해 EKS 기반 기술 검증 내용을 정리했습니다.

**검증 내용**
- Karpenter 기반 EKS 자동 스케일링 구조 구성
- EC2NodeClass, NodePool, IAM Role, Subnet/Security Group discovery 태그 구성 방식 정리
- Pod Pending 발생 시 NodeClaim 생성, EC2 Instance 생성, Node Join, Pod Scheduling 흐름 검증
- Startup/Readiness/Liveness Probe를 분리해 Rollout 중 준비되지 않은 Pod로 트래픽이 유입되는 문제를 줄이는 구조 정리
- ALB, Istio Gateway, Service 단의 트래픽 전달 흐름과 Pod 준비 상태의 관계 검토

**의미**
- Kubernetes 운영에서 단순 리소스 배포가 아니라, 트래픽 처리·확장·배포 안정성을 함께 고려하는 관점 정리
- Cloud & DevOps Architect 직무에서 요구되는 컨테이너 운영 구조 이해도 보완
- 실무 적용 전 구조적 위험 요소와 운영 조건을 검토하는 학습 방식 확보

**관련 글**
- Karpenter 기반 EKS 자동 스케일링 구성
- Kubernetes Probe 설정으로 안정적인 Rollout 구성하기

---

### 3-6. CloudFront + Lambda@Edge 기반 라우팅 구조 검토

**목적**  
도메인별로 서로 다른 오리진 포트로 요청을 전달해야 하는 상황에서, Nginx Reverse Proxy 또는 ALB만 사용하는 방식 외에 CloudFront + Lambda@Edge 기반 라우팅 구조를 검토했습니다.

**검토 내용**
- Custom Domain과 Origin Domain의 역할 분리
- CloudFront Origin Request 단계에서 Lambda@Edge를 사용해 Host Header 기준으로 Origin host/port 매핑
- Route53, CloudFront, Lambda@Edge, Origin Server 간 요청 흐름 정리
- Nginx/ALB/CloudFront+Lambda@Edge 방식의 비용, 안정성, 복잡도 비교

**의미**
- 단순 네트워크 설정이 아니라, 비용·안정성·복잡도를 고려한 요청 전달 구조 설계 관점 확보
- CloudFront, Route53, Lambda@Edge 기반 Edge Routing 구조 이해도 보완
- 서비스 전달 경로를 인프라 아키텍처 관점에서 비교·검토하는 경험 축적

**관련 글**
- 도메인마다 포트가 다른 서버? CloudFront + Lambda@Edge로 해결하기

---

### 3-7. Observability / 로그 수집 구조 검증

**목적**  
Kubernetes 환경에서 애플리케이션 로그를 수집·전달·검색 가능한 구조로 구성하기 위해 Fluentd와 OpenSearch 기반 로그 파이프라인을 검증했습니다.

**검증 내용**
- Kubernetes 환경에서 Fluentd DaemonSet 기반 로그 수집 구조 검토
- OpenSearch를 활용한 로그 저장 및 검색 구조 정리
- 컨테이너 로그 수집, 전달, 조회 흐름 문서화
- 운영 환경에서 로그 기반 장애 분석을 수행하기 위한 기본 구조 검토
- Uptime Kuma Kubernetes 운영 및 SQLite → MariaDB 마이그레이션 구조 정리

**의미**
- 단순 모니터링 도구 사용이 아니라, 운영 중 장애 분석에 필요한 로그 수집·검색 흐름 이해
- CloudWatch 외 Kubernetes 기반 로그 수집 구조에 대한 이해도 보완
- 장애 대응과 운영 안정성을 위한 Observability 관점 확장

**관련 글**
- Kubernetes 환경에서 Fluentd + OpenSearch 로그 수집 구축
- Uptime Kuma Kubernetes 환경 운영 및 SQLite → MariaDB 마이그레이션

---

## 4. Technical Blog Highlights

기술 블로그에는 실무와 기술 검증 과정에서 정리한 Cloud / DevOps / Kubernetes 관련 내용을 기록하고 있습니다.

| 주제 | 내용 | 포트폴리오에서 보여주는 역량 |
|---|---|---|
| Karpenter 기반 EKS 자동 스케일링 | 트래픽 급증 시 Pending Pod, 응답 지연, 수동 증설 한계를 줄이기 위한 자동 확장 구조 검토 | EKS 운영, 스케일링, 비용/성능 균형 |
| Kubernetes Probe 설정 | Rollout 중 준비되지 않은 Pod로 트래픽이 유입되는 문제를 줄이기 위한 Probe 분리 | 배포 안정성, 트래픽 제어 |
| Jenkins Kubernetes Agent | Jenkins 빌드 Agent를 Kubernetes 환경에서 동적으로 활용하는 구조 정리 | CI/CD 확장성 |
| Fluentd + OpenSearch | Kubernetes 로그 수집 및 검색 구조 구성 | Observability, 로그 기반 운영 |
| CloudFront + Lambda@Edge | 도메인별 Origin host/port 라우팅 구조 검토 | Edge Routing, AWS 아키텍처 |
| JMeter 부하 테스트 | 피크 트래픽 상황을 가정한 부하 조건과 API 비율 설계 | 성능 검증, 운영 안정성 |
| AWS Device Farm | 모바일 웹 테스트 환경을 클라우드 기반으로 구성 | QA 자동화, 테스트 환경 개선 |
| ECR Cross Account Mirroring | 계정 간 이미지 전달 구조와 트러블슈팅 정리 | 이미지 전달, Registry 운영 |

블로그: https://blog.yewon.cloud/

---

## 5. Problem Solving Approach

문제를 해결할 때는 단순히 현재 동작 여부만 확인하지 않고, 서비스 구조와 운영 조건을 함께 확인하려고 합니다.

1. **현재 구조와 제약 조건을 먼저 파악합니다.**  
   구성 요소를 바로 바꾸기보다 서비스 흐름, 네트워크 구조, 권한, 배포 방식, 고객사 보안 조건을 먼저 확인합니다.

2. **운영 중 반복될 수 있는 문제를 찾습니다.**  
   한 번의 조치로 끝나는 문제가 아니라, 배포·설치·점검 과정에서 반복되는 병목인지 확인하고 표준화 가능성을 검토합니다.

3. **자동화 가능한 단위를 분리합니다.**  
   이미지 전달, 배포 실행, 리소스 생성, 인증서 갱신, 점검·알림처럼 반복되는 작업은 스크립트나 파이프라인으로 분리할 수 있는지 확인합니다.

4. **다른 사람이 재현 가능한 형태로 문서화합니다.**  
   혼자만 처리할 수 있는 방식보다, 다음 담당자도 같은 기준으로 수행할 수 있도록 절차와 판단 기준을 문서로 남깁니다.

---

## 6. Skills

### Cloud / Infrastructure
`AWS` `EC2` `RDS` `S3` `IAM` `Lambda` `CloudWatch` `Route53` `ALB` `CloudFront` `ECR` `ACM`

### Container / Orchestration
`Kubernetes` `EKS` `Docker` `Docker Compose` `Helm` `Karpenter` `Istio`

### CI/CD / DevOps
`Jenkins` `GitLab` `Nexus` `Registry` `Groovy` `Jenkinsfile` `Terraform` `Shell Script`

### Monitoring / Observability
`CloudWatch` `Fluentd` `OpenSearch` `Uptime Kuma`

### Language / Scripting
`Python` `Shell Script`

### Python Web / API
`Flask` `Django` `Streamlit`

### Database
`MariaDB` `MongoDB`

### Documentation / Operation
`Technical Documentation` `Troubleshooting` `Network Inspection` `Linux`

---

## 7. Direction

앞으로는 Cloud / DevOps / Kubernetes 기반의 구축 자동화와 운영 표준화 역량을 더 확장하고자 합니다. 특히 고객사 환경 제약, 보안 조건, 배포 전달 방식, 운영 안정성을 함께 고려해 실제 운영 가능한 아키텍처를 만드는 역할에 관심이 있습니다.

단순히 기술을 적용하는 것보다, 구축 이후에도 반복 가능하고 안정적으로 운영될 수 있는 구조를 만들고 싶습니다. 이를 위해 CI/CD, IaC, Kubernetes, Observability 영역을 지속적으로 학습하고, 실무에서 마주한 문제와 검증 과정을 블로그와 문서로 정리하고 있습니다.

---

## 8. Links

- Blog: https://blog.yewon.cloud/
- GitHub: https://github.com/yewon4540
