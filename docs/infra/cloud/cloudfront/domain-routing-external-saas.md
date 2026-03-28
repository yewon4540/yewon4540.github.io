---
title: CloudFront를 이용한 도메인 라우팅 및 외부 SaaS 연동 구조 정리
layout: default
parent: CloudFront
grand_parent: Cloud
nav_order: 2
written_at: 2026-03-27
---

# CloudFront를 이용한 도메인 라우팅 및 외부 SaaS 연동 구조 정리

도메인을 단순히 서버에 연결하는 수준을 넘어서,
루트 도메인 리디렉션, 외부 SaaS 연동, 주소 유지까지 처리해야 하는 상황이 있었습니다.

이 글에서는 Route53 + CloudFront + S3를 이용해
도메인을 유연하게 라우팅하는 방법과, 실제 구성 과정에서 확인했던 주의사항을 정리합니다.

---

## 문제/상황

다음과 같은 요구사항이 있었습니다.

- `example.com` 접속 시 → `www.example.com`으로 이동
- `www.example.com`은 외부 SaaS를 사용
- 외부 서비스 도메인으로 이동하지 않고 **브라우저 주소를 유지해야 함**

기존 방식의 문제:

- 단순 DNS 연결만으로는 원하는 동작을 만들기 어려움
- 외부 서비스가 커스텀 도메인 HTTPS를 직접 지원하지 않으면 SSL 문제가 발생할 수 있음
- 외부 서비스에서 리디렉션을 반환하면 브라우저 주소가 변경됨
- SaaS 특성상 내부 라우팅 동작을 직접 제어하기 어려움

결론적으로,

> DNS 설정만으로는 한계가 있었고
> 중간에서 요청을 받아 처리할 프록시 계층이 필요했습니다.

---

## 해결 방법 / 개요

CloudFront를 중심으로 다음 구조를 구성했습니다.

구성 요소:

- Route53 (DNS)
- CloudFront (Reverse Proxy + SSL)
- S3 (루트 도메인 Redirect 처리)
- CloudFront Function (경로 rewrite)

---

## 아키텍처 / 흐름

```text
Route53
 ├─ example.com ──► CloudFront (Redirect)
 │                     └─ S3 → www.example.com
 │
 └─ www.example.com ──► CloudFront (Reverse Proxy)
                           ├─ Function (URI rewrite)
                           └─ Origin (External SaaS)
```

---

## 사전 준비

- Route53 Hosted Zone
- CloudFront Distribution 생성 권한
- ACM 인증서
- 외부 SaaS에서 제공하는 origin endpoint

참고:

- CloudFront에 연결하는 ACM 인증서는 `us-east-1` 리전에 있어야 함
- 루트 도메인(`example.com`)은 Route53에서 보통 Alias 레코드로 연결

---

## 1. CloudFront를 사용하는 이유

일반적인 방식은 아래와 같습니다.

```text
www.example.com → 서버 또는 서비스 endpoint
```

하지만 이번 구조에서는 아래처럼 CloudFront를 중간에 둡니다.

```text
www.example.com → CloudFront → 외부 서비스
```

CloudFront를 사용하는 이유:

- HTTPS를 CloudFront에서 처리할 수 있음
- 외부 서비스 앞단에서 프록시 역할을 수행할 수 있음
- 도메인 구조와 요청 흐름을 제어할 수 있음
- 필요 시 Function 또는 Lambda@Edge로 요청을 추가 가공할 수 있음

즉,

> CloudFront는 단순 CDN이 아니라
> 도메인 라우팅 레이어로 사용할 수 있습니다.

---

## 2. 루트 도메인 리디렉션 (S3 + CloudFront)

루트 도메인(`example.com`)을 `www.example.com`으로 보내는 용도로는
S3 정적 웹사이트 Redirect 기능을 사용할 수 있습니다.

### 2-1) S3 설정

Static Website Hosting:

```text
Redirect all requests to:
Host: www.example.com
Protocol: https
```

### 2-2) CloudFront 설정

Origin:

```text
S3 static website endpoint
```

Behavior:

- Path: `/*`
- Redirect 응답이므로 캐시 정책도 함께 확인

### 2-3) 동작

```text
example.com → CloudFront → S3 → www.example.com
```

---

## 3. 외부 SaaS 연결 (Reverse Proxy)

핵심 구조는 아래와 같습니다.

```text
www.example.com → CloudFront → External SaaS
```

이 방식의 목적은 사용자는 `www.example.com`으로 접속하지만,
실제 콘텐츠는 외부 SaaS에서 제공받도록 구성하는 것입니다.

### 3-1) CloudFront 기본 설정

General:

```text
Alternate Domain Names:
www.example.com
```

```text
Viewer Certificate:
ACM (www.example.com)
```

### 3-2) Origin 설정

```text
Origin domain: service.external-saas.example
Protocol: HTTPS
```

설명:

- origin에는 외부 SaaS가 제공한 endpoint를 설정
- 외부 SaaS의 커스텀 도메인 지원 방식에 따라 추가 설정이 필요할 수 있음
- 서비스에 따라 Host 헤더, Origin Path, Redirect 정책 동작이 다를 수 있으므로 실제 응답을 확인하면서 맞춰야 함

### 3-3) Behavior 설정

- Path: `/*`
- 초기 테스트 시에는 캐시를 최소화하거나 비활성화하여 동작부터 확인
- Viewer Protocol Policy는 HTTPS 기준으로 정리

### 3-4) 동작

```text
User → CloudFront → External SaaS → Response
```

이 구조가 정상 동작하면 브라우저 주소는 유지한 채 외부 SaaS 응답을 전달할 수 있습니다.

---

## 4. CloudFront Function으로 경로 rewrite 하기

외부 문서 서비스나 일부 SaaS는 루트 경로(`/`)로 접근하면
내부적으로 특정 하위 경로로 리디렉션하는 경우가 있습니다.

예를 들면 아래와 같은 형태입니다.

```text
/ → /docs-space
```

이 경우 원본 서비스의 3xx 응답을 그대로 사용하면 주소 유지가 어렵습니다.

### 4-1) 해결 방법

CloudFront Viewer Request 단계에서 URI를 직접 변경합니다.

```javascript
function handler(event) {
    var request = event.request;

    request.uri = "/docs-space" + request.uri;

    return request;
}
```

### 4-2) 적용 위치

- CloudFront → Behavior
- Viewer Request 단계

### 4-3) 동작

```text
/ → /docs-space
```

결과:

- 브라우저 기준 리디렉션이 발생하지 않음
- 주소를 유지한 채 내부 경로로 요청 전달 가능

---

## 5. 구성 중 겪었던 문제와 해결 과정

### 문제 1. DNS 변경 후 접속 결과가 일관되지 않음

- NS 변경 직후 서로 다른 DNS 결과가 조회됨
- 일부 환경은 기존 설정, 일부 환경은 신규 설정을 참조함

해결:

- 전환 전에 기존/신규 DNS 설정을 최대한 동일하게 맞춘 뒤 NS 변경 진행
- DNS 전파 시간을 고려해서 단계적으로 확인

---

### 문제 2. CloudFront 캐시 때문에 Redirect 변경이 바로 반영되지 않음

- S3 redirect 설정을 변경했는데 즉시 반영되지 않음

원인:

- CloudFront가 기존 Redirect 응답을 캐시하고 있었음

해결:

```text
Invalidation: /*
```

---

### 문제 3. 단순 도메인 연결만으로는 외부 SaaS 연동이 실패함

- HTTPS 오류 발생
- 403 또는 예상하지 못한 응답 반환

원인:

- 외부 서비스가 해당 도메인에 대해 직접적인 SSL 또는 라우팅 구성을 지원하지 않음
- 단순 DNS 연결만으로는 원하는 프록시 동작을 만들 수 없음

해결:

- CloudFront Reverse Proxy 구조로 변경
- SaaS의 응답 방식과 redirect 동작을 기준으로 origin 설정 재조정

---

### 문제 4. 특정 경로로 강제 이동되어 주소 유지가 어려움

- `/` 요청 시 내부적으로 `/docs-space` 같은 하위 경로로 이동

해결:

- CloudFront Function으로 URI rewrite 적용

---

## 정리

| 문제 | 해결 방법 |
| --- | --- |
| 루트 → www 이동 | S3 + CloudFront |
| 외부 SaaS 연결 | CloudFront Reverse Proxy |
| SSL 처리 | CloudFront에서 처리 |
| 경로 리디렉션 | CloudFront Function |

---

## 한 줄 정리

CloudFront는 CDN 용도뿐 아니라,
도메인 라우팅과 외부 서비스 연결을 위한 중간 레이어로도 활용할 수 있습니다.
