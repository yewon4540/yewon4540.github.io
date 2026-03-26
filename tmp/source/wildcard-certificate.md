---
title: SSL 서브 도메인 와일드카드(*) 인증서 발급 방법
layout: default
parent: 인증서
grand_parent: Cloud
nav_order: 1
written_at: 2026-03-25
---

# SSL 서브 도메인 와일드카드(*) 인증서 발급 방법

이번 글에서는 **Let's Encrypt**와 **Certbot**을 사용하여 SSL 인증서를 발급하는 방법을 정리합니다.

일반 도메인 인증서뿐 아니라, 여러 서브도메인을 한 번에 커버할 수 있는 **와일드카드 인증서** 발급 방법도 함께 살펴보겠습니다.

## Certbot을 이용한 인증서 발급 방식

Certbot으로 인증서를 발급받는 방식은 대표적으로 아래 3가지가 있습니다.

### 1) standalone 방식

- 웹 서버가 실행 중이지 않은 상태에서 Certbot이 직접 80 포트를 열어 인증을 진행합니다.
- 초기 서버 구성 단계나 Nginx가 아직 올라오지 않은 환경에서 사용하기 좋습니다.

```bash
# ${1}: path, ${2}: domain
docker run -it --rm --name certbot -p 80:80 \
  -v "${1}/etc/letsencrypt:/etc/letsencrypt" \
  -v "${1}/lib/letsencrypt:/var/lib/letsencrypt" \
  certbot/certbot certonly --standalone -d "${2}"
```

### 2) webroot 방식

- Nginx 같은 웹 서버가 이미 실행 중인 환경에서 사용합니다.
- `/.well-known/acme-challenge/` 경로를 웹 서버가 제공할 수 있어야 합니다.
- 80 포트 충돌 없이 인증서를 발급하거나 갱신할 수 있어 운영 환경에서 자주 사용합니다.

```bash
# ${1}: path, ${2}: domain
docker run -it --rm --name certbot \
  -v "${1}/etc/letsencrypt:/etc/letsencrypt" \
  -v "${1}/lib/letsencrypt:/var/lib/letsencrypt" \
  -v "/usr/share/nginx/html:/usr/share/nginx/html" \
  certbot/certbot certonly \
  --webroot -w /usr/share/nginx/html \
  -d "${2}" -d "www.${2}"
```

### 3) Route53 기반 와일드카드 발급 방식 (dns-01)

- AWS Route53을 사용해 DNS 검증 방식으로 인증서를 발급합니다.
- HTTP 포트를 열 필요가 없어서 운영 중인 서비스에 영향을 줄 가능성이 적습니다.
- `*.example.com` 같은 와일드카드 인증서가 필요할 때 유용합니다.

```bash
# ${1}: path, ${2}: domain
docker run -it --rm --name certbot \
  -v "${1}/etc/letsencrypt:/etc/letsencrypt" \
  -v "${1}/lib/letsencrypt:/var/lib/letsencrypt" \
  -e AWS_REGION=ap-northeast-2 \
  certbot/dns-route53 certonly \
  -d "${2}" -d "*.${2}"
```

## 와일드카드 인증서 발급 조건

와일드카드 인증서는 편리하지만, 몇 가지 전제 조건이 필요합니다.

- 도메인이 **Route53**에서 관리되고 있어야 합니다.
- 인증서를 발급하는 서버가 Route53에 접근할 수 있어야 합니다.
- 보통 `~/.aws` 자격 증명 또는 **EC2 IAM Role**을 사용합니다.

최소 권한 예시는 아래와 같습니다.

```json
[
  "route53:ListHostedZonesByName",
  "route53:ListResourceRecordSets",
  "route53:ChangeResourceRecordSets"
]
```

> 위 예시는 AWS 자격 증명이 이미 설정되어 있다는 가정입니다. 
> EC2 환경이라면 IAM Role을 사용하는 방식이 가장 일반적입니다.

## 와일드카드 인증서에서 주의할 점

와일드카드 인증서는 한 단계 하위 서브도메인까지만 커버합니다.

예를 들어 아래 인증서는:

```text
example.com
*.example.com
```

다음과 같은 도메인을 커버할 수 있습니다.

- `example.com`
- `api.example.com`
- `admin.example.com`

하지만 아래처럼 더 깊은 단계의 도메인은 커버하지 못합니다.

- `hello.dev.example.com`

이 경우에는 기준 도메인을 한 단계 더 내려서 별도로 발급해야 합니다.

```text
test.example.com
*.test.example.com
```

예시는 아래와 같습니다.

```bash
docker run -it --rm --name certbot \
  -v "/etc/letsencrypt:/etc/letsencrypt" \
  -v "/var/lib/letsencrypt:/var/lib/letsencrypt" \
  -e AWS_REGION=ap-northeast-2 \
  certbot/dns-route53 certonly \
  -d "test.example.com" -d "*.test.example.com"
```

이렇게 발급하면 `hello.test.example.com` 같은 도메인까지 대응할 수 있습니다.

## 정리

| 방식 | 인증 대상 | 인증 조건 | 사용 상황 |
| --- | --- | --- | --- |
| standalone | `example.com`, `www.example.com` 등 | 도메인이 해당 서버를 가리키고, 80 포트가 비어 있어야 함 | 초기 서버 구성, 웹 서버 미설치 환경 |
| webroot | `example.com`, `www.example.com` 등 | 웹 서버가 실행 중이며 `/.well-known/acme-challenge/` 경로 제공 가능 | 운영 서버, 무중단 갱신 환경 |
| dns-route53 | `example.com`, `*.example.com` 등 | Route53에서 도메인 관리, AWS 자격 증명 필요 | AWS 환경, 와일드카드 인증서 발급 |

운영 환경에서 여러 서브도메인을 함께 관리해야 한다면, `dns-route53` 방식의 와일드카드 인증서가 가장 편리합니다.