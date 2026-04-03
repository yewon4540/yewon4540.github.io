# 박예원 · Cloud / DevOps Engineer

🔗 **블로그:** [https://yewon4540.github.io](https://yewon4540.github.io)

AWS, Kubernetes, CI/CD 파이프라인 중심의 인프라 엔지니어링 기술 블로그입니다.  
실무에서 직접 구성·트러블슈팅한 내용을 기록합니다.

---

## 기술 스택

| 영역 | 기술 |
|---|---|
| Cloud | AWS (EKS, ALB, ACM, CloudFront, ECR, SES) |
| Container / Orchestration | Kubernetes, k3s, Docker |
| CI/CD | Jenkins, Nexus, GitLab |
| Monitoring | Fluentd, OpenSearch, Uptime Kuma |
| QA | JMeter, AWS Device Farm |
| Infra | Nginx, iptables, NCP |

---

## 대표 포스트

- [Karpenter 기반 EKS 자동 스케일링](https://yewon4540.github.io/docs/kubernetes/k8s/eks-karpenter)
- [Jenkins Kubernetes Agent 구성](https://yewon4540.github.io/docs/devops/jenkins/jenkins-agent)
- [Fluentd → OpenSearch 로그 파이프라인](https://yewon4540.github.io/docs/monitoring/fluent/fluentd-opensearch)
- [CloudFront + Lambda@Edge](https://yewon4540.github.io/docs/infra/cloud/cloudfront/lambda-edge)
- [JMeter 부하 테스트](https://yewon4540.github.io/docs/qa/performance-test/jmeter-load-test)

---

## 블로그 카테고리

- **Kubernetes** — EKS, k3s, Karpenter, Probe
- **인프라** — AWS Cloud, Docker, Nginx, Server
- **DevOps** — Jenkins, Nexus, GitLab
- **모니터링** — Fluentd, OpenSearch, Uptime Kuma
- **QA** — JMeter 부하 테스트, AWS Device Farm
- **AI & 머신러닝**
- **커리어&포트폴리오**

---

## 로컬 실행

```bash
bundle install
bundle exec jekyll serve
# → http://localhost:4000
```

## 로컬 관리자 화면

공개 사이트의 `/admin`은 보안을 위해 비활성화되어 있습니다.

```bash
bash scripts/start-local-admin.sh
# 블로그: http://localhost:4000
# 관리자: http://localhost:4000/admin
```

---

## 사이트 기술 스택

- [Jekyll](https://jekyllrb.com)
- [Just the Docs](https://just-the-docs.github.io/just-the-docs/) 테마
- [GitHub Pages](https://docs.github.com/en/pages)
