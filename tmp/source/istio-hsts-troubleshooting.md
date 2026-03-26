---
title: Istio 환경에서 HSTS 미적용 문제 해결 과정
layout: default
parent: 네트워크
grand_parent: Infra
nav_order: 1
written_at: 2026-03-26
---

# Istio 환경에서 HSTS 미적용 문제 해결 과정

MSA 구조에서 서비스별로 HTTPS는 정상적으로 적용되어 있었지만, 보안 점검 과정에서 HSTS가 일부 API 응답에 적용되지 않는 문제를 발견했다.  
이 글에서는 해당 문제를 분석하고, Istio 환경에서 HSTS를 적용하는 과정을 정리한다.

---

## 문제/상황

서비스 구조는 다음과 같다.

- MSA 구조 (FO / GW / API)
- Istio Gateway를 통해 외부 트래픽 유입
- 각 서비스는 도메인 기반으로 통신

보안 점검 결과:

- `https://fo-stg.lamitie.kr` → HSTS 정상 적용
- `https://fo-stg.lamitie.kr/api` → HSTS 미적용

즉, 동일 도메인인데도 일부 경로에서 HSTS가 빠지는 문제가 발생했다.

---

## 해결 방법 / 개요

문제를 해결하기 위해 다음을 확인했다.

- HSTS 적용 위치 확인 (앱 vs 인프라)
- 요청 흐름 분석
- Istio VirtualService에서 헤더 적용

---

## 아키텍처 / 흐름

현재 구조는 아래와 같다.

```
브라우저
  ↓
Istio Gateway
  ↓
FO (Node.js)
  ↓
GW (Spring Boot)
  ↓
API 응답
```

여기서 중요한 점은:

- FO 요청은 FO 서버가 직접 응답 생성
- API 요청은 GW가 응답 생성

---

## 사전 준비

- Kubernetes + Istio 환경
- VirtualService 기반 라우팅 구성
- HTTPS 적용 완료 상태

---

## 1. 문제 원인 분석

처음에는 FO에서 HSTS가 정상 적용되고 있었기 때문에, 전체 서비스에 문제가 없다고 판단했다.

하지만 API 요청을 확인해보니:

```
curl -I https://fo-stg.lamitie.kr/api
```

응답에 `Strict-Transport-Security` 헤더가 존재하지 않았다.

### 1-1) 원인

- FO는 Node.js 애플리케이션에서 직접 HSTS 설정
- GW는 별도 설정 없음
- Istio에서는 HSTS를 추가하지 않음

결과적으로:

- FO 응답 → HSTS 있음
- API 응답 → HSTS 없음

---

## 2. 해결 사고 과정

처음에는 GW 애플리케이션에 HSTS를 추가해야 하는지 고민했다.

하지만 구조를 다시 보면:

```
브라우저 → Istio → 서비스 → Istio → 브라우저
```

즉, 최종적으로 브라우저가 받는 응답은 항상 Istio를 거친다.

따라서 HSTS는 서비스별로 적용하는 것이 아니라, **Istio 레벨에서 통일하는 것이 맞다**고 판단했다.

---

## 3. 해결 방법

Istio VirtualService에 response header를 추가하는 방식으로 해결했다.

```
http:
  - name: "x2bee-gw-http"
    headers:
      response:
        add:
          Strict-Transport-Security: "max-age=31536000; includeSubDomains"
    route:
      - destination:
          host: x2bee-gw-svc
          subset: v1
```

### 3-1) 적용 위치

중요한 점:

- `spec.http[].headers` 위치에 추가해야 함
- `spec` 바로 아래에 넣으면 적용되지 않음

---

## 4. 적용 중 발생한 문제

템플릿 수정 후에도 HSTS가 적용되지 않는 문제가 발생했다.

확인 결과:

- Node.js 템플릿만 수정
- GW(Spring Boot) 템플릿은 수정하지 않음

즉, 서로 다른 Helm chart를 사용하고 있었고, 수정한 템플릿이 실제 GW 서비스에는 반영되지 않았다.

---

## 5. 최종 구조

최종적으로는 다음과 같이 정리했다.

- FO: 애플리케이션 HSTS 제거 (선택)
- GW: Istio VirtualService에서 HSTS 적용
- 이후 전체 서비스에 공통 적용 가능

---

## 6. HSTS 개념 정리

HSTS는 HTTP Strict Transport Security의 약자로, 브라우저가 해당 도메인에 대해 HTTPS만 사용하도록 강제하는 정책이다.

```
Strict-Transport-Security: max-age=31536000; includeSubDomains
```

- max-age: 브라우저가 HTTPS를 강제할 기간 (초 단위)
- includeSubDomains: 하위 도메인까지 적용

중요한 점:

- HSTS는 서버가 아니라 브라우저가 동작을 변경하는 정책
- 내부 서비스 간 통신에는 영향 없음

---

## 참고

- Istio VirtualService 공식 문서
- OWASP HSTS 정책 가이드
