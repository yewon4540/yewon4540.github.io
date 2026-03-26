---
title: SMTP 개념과 AWS SES, NCP SENS 기반 메일 발송 구성 정리
layout: default
parent: 이메일
grand_parent: Cloud
nav_order: 1
written_at: 2026-03-26
---

# SMTP 개념과 AWS SES, NCP SENS 기반 메일 발송 구성 정리

AWS 기반 인프라에서 메일 발송 기능을 구성하면서, SMTP와 클라우드 메일 서비스 구조를 정리합니다.

---

## 문제/상황

애플리케이션에서 메일 발송 기능은 거의 필수적으로 요구됩니다.

하지만 실제로 구성할 때는 아래와 같은 고민이 생깁니다.

- 메일은 어떻게 보내는가?
- SMTP는 무엇인가?
- AWS에서는 어떤 서비스를 쓰는가?
- NCP에서는 어떻게 구성되는가?

특히 클라우드 환경에서는  
단순히 “메일을 보낸다”가 아니라

- 어떤 서비스(SaaS)를 사용할지
- SMTP를 사용할지 API를 사용할지

까지 선택해야 합니다.

---

## 해결 방법 / 개요

이 글에서는 아래 내용을 정리합니다.

- SMTP 개념
- AWS SES와 NCP SENS 구조 차이
- 실제 메일 발송 구성 방식
- SMTP 기반 설정 흐름

---

## 아키텍처 / 흐름

```
[Application]
      ↓
[SMTP Server or Cloud Email Service]
      ↓
[수신자 메일 서버]
```

애플리케이션은 메일을 직접 보내지 않고  
중간 서버를 통해 전달합니다.

---

## 사전 준비

- 클라우드 환경 (AWS 또는 NCP)
- 메일 발송용 계정
- SMTP 서버 정보 또는 API 사용 여부 결정
- 애플리케이션 (Python, Spring 등)

---

## 1. SMTP란 무엇인가

SMTP는 메일을 전송하기 위한 프로토콜입니다.

메일 전송 과정은 다음과 같습니다.

```
Application → SMTP Server → Recipient Mail Server
```

핵심 특징은 아래와 같습니다.

- 메일을 직접 보내지 않고 SMTP 서버에 위임
- 인증 기반 (ID / Password)
- 포트 기반 통신

주요 포트

- 25 : 기본 포트 (제한되는 경우 많음)
- 587 : TLS (일반적으로 가장 많이 사용)
- 465 : SSL

---

## 2. AWS SES와 NCP SENS

### AWS SES

AWS에서는 SES(Simple Email Service)를 제공합니다.

특징

- 이메일 전송 전용 서비스
- SMTP 방식 지원
- API 방식 지원
- 대량 메일 발송 가능

---

### NCP SENS

NCP에서는 SENS(Simple & Easy Notification Service)를 제공합니다.

특징

- 이메일 + SMS + Push 통합 서비스
- SMTP 방식 지원
- API 방식 지원
- 알림 중심 서비스

---

### 차이 정리

| 항목 | SES | SENS |
| --- | --- | --- |
| 목적 | 이메일 전용 | 통합 알림 |
| 이메일 발송 | O | O |
| SMTP 지원 | O | O |
| 확장성 | 이메일 중심 | 다양한 채널 |

정리하면

- SES → 이메일 특화
- SENS → 알림 통합 서비스

---

## 3. 메일 발송 방식 선택

메일 발송은 크게 두 가지 방식이 있습니다.

### 1) SMTP 방식

```
Application → SMTP Server → Mail
```

- 표준 방식
- 대부분의 언어에서 지원
- 설정이 단순

---

### 2) API 방식

```
Application → Email API → Mail
```

- 클라우드 서비스 전용 방식
- 추가 기능 (템플릿, 통계 등)
- 서비스 종속성 존재

---

## 4. 실제 SMTP 설정 흐름

SMTP를 사용할 경우 필요한 정보는 단순합니다.

- SMTP Host
- Port
- ID / Password

예 (Python)

```python
import smtplib

smtp = smtplib.SMTP("smtp.ncloud.com", 587)
smtp.starttls()
smtp.login("SMTP_ID", "SMTP_PASSWORD")

message = "Subject: test\n\nhello"
smtp.sendmail("from@example.com", "to@example.com", message)

smtp.quit()
```

구성 흐름은 다음과 같습니다.

1. SMTP 서버 연결
2. TLS 시작
3. 인증
4. 메일 전송

---

## 5. 클라우드 환경에서 고려할 점

SMTP는 단순하지만 클라우드에서는 몇 가지 추가 고려가 필요합니다.

### 네트워크

- 외부 SMTP 서버 접근 가능 여부
- 포트(587, 465) 허용 여부

---

### 보안

- 계정 정보 관리
- 코드에 직접 입력하지 않도록 분리

예

- Parameter Store
- Secret Manager

---

### 제한 사항

- 일부 클라우드는 25번 포트 차단
- SMTP 서버별 발송 제한 존재

---

## 정리

메일 발송은 단순한 기능처럼 보이지만, 실제로는 다음 요소로 구성됩니다.

- 전송 프로토콜 (SMTP)
- 클라우드 서비스 (SES, SENS)
- 전송 방식 (SMTP vs API)

AWS와 NCP 모두 메일 발송 기능을 제공하지만

- AWS → SES (이메일 중심)
- NCP → SENS (알림 통합)

이라는 차이가 있습니다.

SMTP를 이해하면  
어떤 환경에서도 동일한 방식으로 메일 발송 구성을 할 수 있습니다.

---

## 참고

- SMTP는 가장 기본적인 메일 전송 방식으로, 거의 모든 환경에서 사용 가능
- 클라우드 서비스는 SMTP 위에 추가 기능을 제공하는 구조
- 단순 구성은 SMTP, 확장 기능은 API 방식이 유리
