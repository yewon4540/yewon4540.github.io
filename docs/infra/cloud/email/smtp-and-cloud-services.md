---
title: SMTP와 클라우드 메일 서비스 (SES / SENS) 구성하기
layout: default
parent: Email
grand_parent: Cloud
nav_order: 1
written_at: 2026-03-27
---

# SMTP와 클라우드 메일 서비스 (SES / SENS) 구성하기

애플리케이션에서 메일 발송 기능을 구성하면서,
SMTP와 클라우드 메일 서비스의 관계를 정리했습니다.

---

## 문제/상황

애플리케이션에서 메일 발송은 거의 필수 기능이지만,
실제 구성 시 아래와 같은 선택이 필요합니다.

- SMTP는 무엇인가?
- AWS SES와 NCP SENS의 차이는?
- SMTP 방식과 API 방식 중 어느 것을 택할까?
- 클라우드 환경에서 특별히 고려할 점은?

---

## 해결 방법 / 개요

이 글에서는 아래 내용을 정리합니다.

- SMTP 개념 및 동작 방식
- AWS SES와 NCP SENS 구조 비교
- SMTP vs API 방식 선택 기준
- 클라우드 환경 운영 시 주의사항

---

## 아키텍처 / 흐름

```text
[Application]
      ↓
[SMTP Server or Cloud Email Service]
      ↓
[Recipient Mail Server]
```

애플리케이션은 메일을 직접 보내지 않고,
중간 서버를 거쳐 전달합니다.

---

## 사전 준비

- AWS 또는 NCP 계정
- SES/SENS 기본 접근 권한
- 메일 발송용 계정 (SMTP ID/Password)
- 테스트용 애플리케이션

---

## 1. SMTP란 무엇인가

SMTP (Simple Mail Transfer Protocol)는
메일을 전송하기 위한 표준 프로토콜입니다.

기본 동작:

```text
Application → SMTP Server → Recipient Mail Server
```

핵심 특징:

- 애플리케이션이 SMTP 서버에 메일 전달을 위임
- ID/Password 기반 인증
- 포트 기반 통신

주요 포트:

- `25`: 기본 포트 (대부분의 클라우드에서 차단)
- `587`: TLS (가장 일반적)
- `465`: SSL

---

## 2. AWS SES와 NCP SENS 비교

### AWS SES (Simple Email Service)

특징:

- 이메일 발송 전용 서비스
- SMTP 방식과 API 방식 모두 지원
- 대량 메일 발송 최적화
- 세밀한 통계 및 로그 제공

### NCP SENS (Simple & Easy Notification Service)

특징:

- 이메일 + SMS + Push 통합 서비스
- SMTP 방식과 API 방식 모두 지원
- 알림 채널 통합 관리
- 멀티 문자/이메일 템플릿 지원

### 비교

| 항목 | SES | SENS |
| --- | --- | --- |
| 주 목적 | 이메일 전용 | 통합 알림 |
| SMTP 지원 | ✓ | ✓ |
| API 지원 | ✓ | ✓ |
| SMS | ✗ | ✓ |
| 특화 영역 | 대량 이메일 | 멀티 채널 |

정리:

- **SES**: 이메일에만 집중하는 서비스
- **SENS**: 여러 알림 채널을 함께 운영하려면 유리

---

## 3. 메일 발송 방식: SMTP vs API

### SMTP 방식

```text
Application → SMTP Server → Mail
```

장점:

- 표준 프로토콜 (대부분 언어 지원)
- 설정이 단순
- 벤더 독립적

단점:

- 템플릿/통계 미지원
- 에러 처리가 상대적으로 복잡

### API 방식

```text
Application → Email API → Mail
```

장점:

- 템플릿/변수 치환 가능
- 상세한 통계 제공
- 에러 응답이 구조화됨

단점:

- 서비스에 종속적
- 추가 학습 필요

---

## 4. SMTP 기반 구성 예제

### Python 예제

```python
import smtplib
from email.mime.text import MIMEText

# 1. SMTP 연결
smtp_server = "email-smtp.<region>.amazonaws.com"  # AWS SES
port = 587

smtp = smtplib.SMTP(smtp_server, port)
smtp.starttls()

# 2. 인증
smtp.login("SMTP_USERNAME", "SMTP_PASSWORD")

# 3. 메일 구성
message = MIMEText("메일 본문")
message['Subject'] = "테스트"
message['From'] = "sender@example.com"
message['To'] = "recipient@example.com"

# 4. 발송
smtp.sendmail("sender@example.com", "recipient@example.com", message.as_string())

# 5. 종료
smtp.quit()
```

흐름정리:

1. SMTP 서버 연결
2. TLS 시작
3. 인증 (SMTP 계정)
4. 메일 구성 및 발송
5. 연결 종료

### 주의사항

- SMTP 계정 정보는 `Parameter Store` 또는 `Secret Manager`에서 관리
- 포트 587, 465는 클라우드 보안 그룹에서 허용 필요
- 포트 25는 대부분 차단됨

---

## 5. API 기반 구성 예제 (간단히)

### AWS SES SDK 예제 (Python)

```python
import boto3

ses_client = boto3.client('ses', region_name='ap-northeast-2')

response = ses_client.send_email(
    Source='sender@example.com',
    Destination={'ToAddresses': ['recipient@example.com']},
    Message={
        'Subject': {'Data': '테스트'},
        'Body': {'Text': {'Data': '메일 본문'}}
    }
)
```

API 방식의 장점:

- 템플릿 기반 발송 가능
- 응답에 `MessageId` 포함으로 추적 용이
- 구조화된 에러 처리

---

## 6. 클라우드 환경 운영 시 고려사항

### 6-1) 네트워크 설정

- SMTP 포트(587, 465) 허용 필요
- IAM 권한 또는 접근 키 설정
- VPC 내부 통신인 경우 엔드포인트 설정

### 6-2) 보안

- SMTP 계정 정보는 환경변수/비밀 저장소 사용
- 코드에 직접 포함 금지
- TLS 사용 강제

```python
# 나쁜 예
password = "abc123"

# 좋은 예
import os
password = os.getenv('SMTP_PASSWORD')
```

### 6-3) 발송 제한

- AWS SES: 초기 account는 하루 발송량 제한 (제한 해제 신청 필요)
- NCP SENS: 서비스별 발송 한도 설정
- 구성 전에 서비스 제한 확인 필수

### 6-4) 모니터링

- 발송 성공/실패율 확인
- 수신 거부(bounce/complaint) 모니터링
- CloudWatch / SENS Dashboard 활용

---

## 정리

메일 발송은 표면상 단순하지만, 다음 계층으로 구성됩니다.

- **프로토콜**: SMTP (표준)
- **클라우드 서비스**: SES (AWS) / SENS (NCP)
- **전송 방식**: SMTP (단순) vs API (확장)

선택 기준:

- 단순 메일 → SMTP 기반
- 템플릿/통계 필요 → API 기반
- 멀티 채널 → NCP SENS
- 이메일 전용 → AWS SES

SMTP를 이해하면 어떤 환경에서도 기본 메일 발송 구성이 가능합니다.

---

## 참고

- SMTP는 가장 기본적인 메일 전송 표준 (거의 모든 환경 지원)
- 클라우드 서비스는 SMTP 위에 추가 기능 제공
- 초기 구성은 SMTP, 확장 시 API 선택 권장
