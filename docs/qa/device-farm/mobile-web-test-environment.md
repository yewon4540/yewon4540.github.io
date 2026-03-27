---
title: AWS Device Farm을 이용한 모바일 웹 테스트 환경 구성
layout: default
parent: Device Farm
grand_parent: QA
nav_order: 1
written_at: 2026-03-26
---

# AWS Device Farm을 이용한 모바일 웹 테스트 환경 구성

모바일 웹 서비스를 다양한 디바이스에서 검증하기 위해 AWS Device Farm을 도입했고,
초기 세팅과 운영 시 확인한 포인트를 정리했습니다.

---

## 문제/상황

모바일 웹 서비스를 테스트할 때 아래와 같은 문제가 있었습니다.

- 실제 다양한 디바이스(iPhone, Galaxy 등)를 모두 확보하기 어려움
- OS/브라우저별 화면 깨짐 여부 확인이 어려움
- QA 환경 통합 테스트 시 디바이스 의존도가 높음

특히 모바일 서비스 특성상 아래 항목이 디바이스마다 다르게 동작할 수 있습니다.

- 화면 레이아웃
- 결제 흐름
- 브라우저 동작

그래서 실제 디바이스 기반 테스트 환경이 필요했습니다.

---

## 해결 방법 / 개요

AWS Device Farm을 활용해 다음 방식으로 환경을 구성했습니다.

구성 요소:

- Remote Access 기반 수동 테스트
- 실제 디바이스(Android / iOS) 사용
- Free Trial(1000 device minutes)로 초기 검증

---

## 아키텍처 / 흐름

```text
테스터 → AWS Device Farm → 실제 모바일 디바이스 → 브라우저 접속 → 웹 서비스 테스트
```

---

## 사전 준비

- AWS 계정
- 테스트할 웹 서비스 URL
- Device Farm 접근 권한

---

## 1. Device Farm 프로젝트 생성

AWS Console에서 Device Farm 프로젝트를 생성합니다.

```text
Device Farm → Mobile Device Testing → Projects → Create mobile project
```

프로젝트 이름은 테스트 목적에 맞게 생성합니다.

---

## 2. Remote Access 세션 생성

모바일 웹 테스트는 앱 업로드가 아니라
Remote Access 방식으로 진행했습니다.

```text
Device Farm → Remote access → Create session
```

설정 항목:

- 디바이스 선택 (iOS / Android)
- 세션 시작

---

## 3. 디바이스 선택 기준

초기 검증 단계에서는 디바이스를 과도하게 선택하지 않는 것이 중요합니다.

예시:

- Android: Galaxy S22, Galaxy S21, Pixel 7
- iOS: iPhone 13, iPhone 14

운영 팁:

- 초기에는 4~5대 수준 권장
- 화면 크기/OS 버전 차이를 우선적으로 커버

---

## 4. 테스트 방법

세션 시작 후 실제 스마트폰 화면이 원격으로 제공됩니다.

테스트 순서:

1. 모바일 브라우저 실행
2. 웹 서비스 URL 접속
3. 주요 기능 시나리오 검증

테스트 항목 예시:

- 메인 페이지 로딩
- 상품 리스트/상세
- 로그인
- 장바구니
- 결제 페이지 이동

---

## 5. 사용량(Free Trial 1000분) 확인

Device Farm은 `device minute` 기준으로 사용량이 차감됩니다.

예시:

- 디바이스 1대 × 10분 = 10분 차감
- 디바이스 2대 × 10분 = 20분 차감

남은 무료 시간 확인 위치:

```text
Device Farm → Projects 화면 상단
```

예시 문구:

```text
You have 996 free trial minutes remaining
```

---

## 6. 사용 시 주의사항

### 6-1) 디바이스 선택

- 디바이스 수가 많을수록 사용량이 빠르게 소진됨
- 초기에는 3~5대 수준으로 제한

### 6-2) 세션 시간

- 세션 시간 = 비용
- 테스트 목적에 맞게 짧게 운영

### 6-3) Remote Access 특성

- 세션 단위로 디바이스가 할당됨
- 테스트마다 세션을 새로 생성해야 함

---

## 7. Remote Access 외 선택 가능한 옵션

Remote Access 외에도 아래 옵션을 상황에 맞게 선택할 수 있습니다.

- Automated Test
  - Appium, XCTest, Espresso 등 자동화 테스트 실행
- Custom Environment
  - 앱/테스트 실행 전 초기 상태 구성
- Device Pool
  - 디바이스 그룹을 정의해 반복 테스트 간 일관성 확보
- Test Reports / Artifacts
  - 로그, 스크린샷, 비디오 기반 결과 분석

초기에는 Remote Access로 수동 검증을 진행하고,
회귀 테스트가 늘어나면 Automated Test로 확장하는 방식이 운영에 유리합니다.

---

## 8. 사용 사례

Device Farm은 다음과 같은 경우에 활용할 수 있습니다.

- 모바일 웹 서비스 QA 테스트
- 다양한 디바이스 화면 검증
- OS/브라우저 호환성 테스트

특히 초기 단계에서는
실제 디바이스 기반 테스트 필요성을 검증하는 용도로 적합합니다.

---

## 참고

- Device Farm Free Trial은 1000 device minutes 제공
- Remote Access 세션 시간과 Trial minutes는 서로 다른 개념
- Trial minutes는 Projects 화면에서 확인 가능
