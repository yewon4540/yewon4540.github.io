---
title: CloudFront를 이용한 도메인 라우팅 및 외부 SaaS 연동 구조 정리
layout: default
parent: Cloud
grand_parent: Infra
nav_order: 2
written_at: 2026-03-27
---

# CloudFront를 이용한 도메인 라우팅 및 외부 SaaS 연동 구조 정리

도메인을 단순히 서버에 연결하는 수준을 넘어서,  
루트 도메인 리디렉션, 외부 SaaS 연동, 주소 유지까지 처리해야 하는 상황이 생겼다.

이 글에서는 Route53 + CloudFront + S3를 이용해  
도메인을 유연하게 라우팅하는 방법과, 실제 겪은 문제 해결 과정을 정리한다.

---

## 문제/상황

다음과 같은 요구사항이 있었다.

- `x2bee.com` 접속 시 → `www.x2bee.com`으로 이동
- `www.x2bee.com`은 외부 서비스(imweb, GitBook 등)를 사용
- 외부 서비스 도메인으로 이동하지 않고 **주소를 유지해야 함**

기존 방식의 문제:

- 단순 CNAME 연결 시
  - 외부 서비스에서 SSL을 제공하지 않으면 HTTPS 실패
  - 또는 리디렉션 발생 → 주소 변경됨
- SaaS 특성상 내부 설정을 제어할 수 없음

결론적으로,

> DNS만으로는 해결이 불가능했고  
> 중간에 프록시 계층이 필요했다.

---

## 해결 방법 / 개요

CloudFront를 중심으로 다음 구조를 구성했다.

구성 요소:

- Route53 (DNS)
- CloudFront (Reverse Proxy + SSL)
- S3 (Redirect 처리)
- CloudFront Function (경로 rewrite)

---

## 아키텍처 / 흐름

```
Route53
 ├─ x2bee.com ──► CloudFront (Redirect)
 │                     └─ S3 → www.x2bee.com
 │
 └─ www.x2bee.com ──► CloudFront (Reverse Proxy)
                           ├─ Function (URI rewrite)
                           └─ Origin (External SaaS)
```

---

## 사전 준비

- Route53 Hosted Zone
- CloudFront Distribution 생성 권한
- ACM 인증서 (www.x2bee.com)
- 외부 서비스 endpoint (imweb, gitbook 등)

---

## 1. CDN을 사용하는 이유

일반적인 방식:

```
www.x2bee.com → A 레코드 → 서버 IP
```

하지만 이번 구조에서는:

```
www.x2bee.com → CloudFront → 외부 서비스
```

CloudFront를 사용하는 이유:

- SSL을 직접 처리할 수 있음
- 외부 서비스 앞단에서 프록시 역할 수행 가능
- 도메인 구조를 통제할 수 있음

즉,

> CloudFront는 단순 CDN이 아니라  
> "도메인 라우팅 레이어"로 사용된다.

---

## 2. 루트 도메인 리디렉션 (S3 + CloudFront)

### S3 설정

Static Website Hosting:

```
Redirect all requests to:
Host: www.x2bee.com
Protocol: https
```

---

### CloudFront 설정

Origin:

```
S3 static website endpoint
```

Behavior:

- Path: /*
- Cache: Enabled

---

### 동작

```
x2bee.com → CloudFront → S3 → www.x2bee.com
```

---

## 3. 외부 SaaS 연결 (Reverse Proxy)

### 핵심 구조

```
www.x2bee.com → CloudFront → external SaaS
```

---

### CloudFront 설정

#### General

```
Alternate Domain Names:
www.x2bee.com
```

```
Viewer Certificate:
ACM (www.x2bee.com)
```

---

#### Origin

```
Origin domain: x2bee.imweb.me
Protocol: HTTPS
```

Custom Header:

```
Host: x2bee.imweb.me
```

설명:

- 외부 서비스는 Host 기반으로 동작
- 그대로 전달하면 403 발생 가능

---

#### Behavior

- Path: /*
- Cache: Disabled (초기)
- HTTPS redirect

---

### 동작

```
User → CloudFront → imweb → Response
```

브라우저 주소는 유지됨

---

## 4. CloudFront Function (경로 rewrite)

GitBook 같은 경우:

```
/ → /x2bee-docs (307 redirect)
```

이 상태에서는 주소 유지가 불가능하다.

---

### 해결 방법

CloudFront에서 URI를 직접 변경

```javascript
function handler(event) {
    var request = event.request;

    request.uri = "/x2bee-docs" + request.uri;

    return request;
}
```

---

### 적용 위치

- CloudFront → Behavior
- Viewer Request 단계

---

### 동작

```
/ → /x2bee-docs
```

결과:

- 리디렉션 없음
- 주소 유지됨

---

## 5. 내가 겪은 문제와 해결 과정

### 문제 1. DNS 변경 후 접속 불안정

- NS 변경 시 서로 다른 DNS 결과 발생
- 일부는 기존, 일부는 신규 설정 사용

해결:

- 기존/신규 DNS 동일하게 구성 후 NS 변경

---

### 문제 2. CloudFront 캐시 문제

- S3 redirect 변경했는데 반영 안됨

원인:

- CloudFront가 301 응답 캐싱

해결:

```
Invalidation: /*
```

---

### 문제 3. CNAME으로 외부 서비스 연결 실패

- HTTPS handshake failure
- 403 발생

원인:

- 외부 서비스에서 해당 도메인 SSL 미지원

해결:

- CloudFront Reverse Proxy 구조로 변경

---

### 문제 4. GitBook 리디렉션 문제

- `/` → `/x2bee-docs` 강제 이동

해결:

- CloudFront Function으로 URI rewrite

---

## 정리

| 문제 | 해결 방법 |
|---|---|
루트 → www 이동 | S3 + CloudFront |
외부 SaaS 연결 | CloudFront Reverse Proxy |
SSL 문제 | CloudFront에서 처리 |
경로 리디렉션 | CloudFront Function |

---

## 한 줄 정리

CloudFront는 CDN이 아니라,  
도메인 라우팅과 외부 서비스 연결을 위한 중간 레이어로 사용할 수 있다.
