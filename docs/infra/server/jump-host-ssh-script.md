---
title: 점프 서버를 거쳐 환경별 서버에 SSH 접속하기 (sshpass + ProxyCommand)
layout: default
parent: Server
grand_parent: 인프라
nav_order: 3
written_at: 2026-03-25
---

# 점프 서버를 거쳐 환경별 서버에 SSH 접속하기 (sshpass + ProxyCommand)
운영 서버에 직접 접근할 수 없는 환경에서, 점프 서버를 거쳐 `dev` / `stg` / `prd` 서버에 접속하기 위해 사용했던 SSH 스크립트를 정리해보았습니다.

---

## 1. 발단

운영 환경에서는 보안상 이유로 외부에서 애플리케이션 서버나 운영 서버에 바로 SSH 접속을 허용하지 않는 경우가 많습니다.

이럴 때 보통은 **점프 서버(Jump Host, Bastion Host)** 를 하나 두고,
외부 사용자는 먼저 이 서버에 접속한 뒤 내부 서버로 다시 이동하는 구조를 사용합니다.

그런데 매번 아래 과정을 반복하는 것은 생각보다 번거롭습니다.

- 점프 서버 주소 입력
- 점프 서버 계정 입력
- 내부 서버 주소 입력
- 환경별 서버(`dev`, `stg`, `prd`) 구분
- 키 파일 지정

그래서 한 번의 명령으로 원하는 환경에 접속할 수 있도록,
간단한 Bash 스크립트를 만들어 사용하게 되었습니다.

---

## 2. 스크립트가 하는 일

이 스크립트는 크게 아래 역할을 수행합니다.

1. 점프 서버 접속 정보 정의
2. 대상 서버(`dev`, `stg`, `prd`) 중 하나 선택
3. 옵션(`-t dev`) 또는 대화형 입력으로 환경 결정
4. `ProxyCommand`를 사용하여 점프 서버를 경유한 SSH 연결 수행

즉,
사용자는 내부 서버에 직접 접근하는 것이 아니라,
**점프 서버를 프록시처럼 거쳐 최종 대상 서버에 접속**하게 됩니다.

---

## 3. 비식별화한 예시 스크립트

실제 IP, 계정, 비밀번호, 키 파일명은 제거하고 구조만 남긴 예시는 아래와 같습니다.

```bash
#!/bin/bash

JUMP_HOST="jump.example.com"
JUMP_PORT="22"
JUMP_USER="jumpuser"
JUMP_PASS="REDACTED_PASSWORD"

PEM_KEY="your-target-key.pem"
TARGET_USER="ubuntu"

select_target() {
    echo "=============================="
    echo "접속할 환경을 선택하세요:"
    echo "1) dev  (10.0.10.11)"
    echo "2) stg  (10.0.20.11)"
    echo "3) prd  (10.0.30.11)"
    echo "=============================="
    read -p "번호를 입력하세요 (1/2/3): " choice

    case $choice in
        1) TARGET_HOST="10.0.10.11" ;;
        2) TARGET_HOST="10.0.20.11" ;;
        3) TARGET_HOST="10.0.30.11" ;;
        *)
            echo "❌ 잘못된 입력입니다. 다시 실행해주세요."
            exit 1
            ;;
    esac
}

while getopts "t:" opt; do
  case $opt in
    t)
      case $OPTARG in
        dev) TARGET_HOST="10.0.10.11" ;;
        stg) TARGET_HOST="10.0.20.11" ;;
        prd) TARGET_HOST="10.0.30.11" ;;
        *)
          echo "❌ 잘못된 옵션입니다. (dev / stg / prd 중 선택)"
          exit 1
          ;;
      esac
      ;;
  esac
done

if [ -z "$TARGET_HOST" ]; then
    select_target
fi

echo "🔗 선택된 서버: $TARGET_HOST"
echo "🚀 SSH 접속을 시작합니다..."

sshpass -p "$JUMP_PASS" ssh \
  -o StrictHostKeyChecking=no \
  -o ProxyCommand="sshpass -p $JUMP_PASS ssh -o StrictHostKeyChecking=no -p $JUMP_PORT $JUMP_USER@$JUMP_HOST -W %h:%p" \
  -i $PEM_KEY \
  $TARGET_USER@$TARGET_HOST
```

---

## 4. 구성 요소 해석

### 4-1. 점프 서버 정보

```bash
JUMP_HOST="jump.example.com"
JUMP_PORT="22"
JUMP_USER="jumpuser"
JUMP_PASS="REDACTED_PASSWORD"
```

이 부분은 외부에서 먼저 접속해야 하는 점프 서버 정보입니다.

즉,
직접 `dev` 서버로 들어가는 것이 아니라,
먼저 점프 서버에 로그인한 뒤 그 세션을 이용해 최종 대상 서버로 이동하게 됩니다.

### 4-2. 최종 대상 서버 정보

```bash
PEM_KEY="your-target-key.pem"
TARGET_USER="ubuntu"
```

최종 접속 대상 서버에 붙을 때 사용하는 계정과 키 파일입니다.

보통 내부 서버는 패스워드 인증보다 **PEM 키 기반 인증**을 사용하므로,
점프 서버는 비밀번호로 통과하고 최종 서버는 키로 접속하는 혼합 형태가 될 수 있습니다.

### 4-3. 환경 선택 함수

```bash
select_target()
```

이 함수는 사용자가 `dev`, `stg`, `prd` 중 어느 환경에 접속할지 고르게 해줍니다.

숫자를 입력하면 해당 환경의 IP를 `TARGET_HOST` 변수에 넣어주고,
잘못 입력했을 경우에는 종료합니다.

### 4-4. 옵션 파싱

```bash
./aww_ssh.sh -t dev
```

대화형 입력 없이도 바로 접속할 수 있도록 `getopts`로 `-t` 옵션을 처리하고 있습니다.

즉,

- `-t dev`
- `-t stg`
- `-t prd`

형태로 바로 원하는 환경에 붙을 수 있습니다.

### 4-5. 핵심: `ProxyCommand`

가장 중요한 부분은 아래 구문입니다.

```bash
-o ProxyCommand="sshpass -p $JUMP_PASS ssh -o StrictHostKeyChecking=no -p $JUMP_PORT $JUMP_USER@$JUMP_HOST -W %h:%p"
```

이 옵션은 SSH가 최종 대상 서버에 접속할 때,
직접 연결하지 않고 **점프 서버를 중간 프록시처럼 사용**하도록 만듭니다.

여기서 `-W %h:%p` 는 현재 접속하려는 최종 목적지의 호스트와 포트로 데이터를 그대로 전달하라는 뜻입니다.

즉 흐름은 아래와 같습니다.

1. 로컬 PC에서 점프 서버로 SSH 접속
2. 점프 서버가 최종 대상 서버로 트래픽 전달
3. 최종 대상 서버에 PEM 키로 로그인

---

## 5. 실행 흐름

이 스크립트는 두 가지 방식으로 사용할 수 있습니다.

### 방법 1) 대화형 선택

```bash
./aww_ssh.sh
```

실행하면 `1) dev`, `2) stg`, `3) prd` 메뉴가 뜨고,
선택한 서버로 접속합니다.

### 방법 2) 옵션으로 바로 지정

```bash
./aww_ssh.sh -t dev
./aww_ssh.sh -t stg
./aww_ssh.sh -t prd
```

운영 중 자주 접속하는 환경이 정해져 있다면 이 방식이 더 편합니다.

---

## 6. 이 방식의 장점

이 스크립트 방식의 장점은 생각보다 분명합니다.

- 운영 환경별 접속 주소를 외우지 않아도 됨
- 점프 서버 경유 접속을 한 번의 명령으로 단순화 가능
- 대화형/옵션형 둘 다 지원 가능
- 내부망 서버 직접 노출 없이 운영 가능

특히 여러 개발자나 운영자가 공통된 접속 패턴을 사용해야 할 때,
이런 래퍼 스크립트는 의외로 생산성이 좋습니다.

---

## 7. 주의할 점

이 스크립트에는 사용 편의성을 우선한 몇 가지 선택이 들어가 있습니다.

### 7-1. 비밀번호 하드코딩

```bash
JUMP_PASS="REDACTED_PASSWORD"
```

이 스크립트는 점프 서버 비밀번호를 직접 넣어,
사용자가 별도 입력 없이 바로 접속할 수 있게 만든 형태입니다.

즉, 접속 절차를 줄이고 반복 작업을 단순화하는 데 초점을 둔 구성이라고 볼 수 있습니다.

### 7-2. `StrictHostKeyChecking=no`

이 옵션은 SSH 접속 시 호스트 키 확인 과정을 생략하여,
처음 접속하는 서버에도 더 빠르게 붙을 수 있도록 돕습니다.

즉, 매번 확인 메시지에 응답하지 않고 바로 접속 흐름을 이어가기 위한 설정입니다.

### 7-3. 스크립트 유출 시 위험

점프 서버 주소, 환경 구성, 내부 서버 대역 정보가 하나의 스크립트에 모여 있으므로,
이 파일 자체가 접속 편의성을 위한 실행 진입점 역할을 하게 됩니다.

그래서 실제 사용 시에는 개인 실행 스크립트, 팀 내부 스크립트, 운영용 도구처럼
관리 목적에 맞게 다루는 경우가 많습니다.

---

## 8. 마무리

점프 서버를 거쳐 내부 서버에 접속하는 구조는 인프라 운영에서 꽤 흔하게 사용됩니다.

그리고 이런 구조는 한 번 익숙해지면 당연해 보이지만,
막상 매번 수동으로 접속하려고 하면 은근히 귀찮고 실수도 생깁니다.

이번 스크립트는 아주 복잡한 자동화는 아니지만,
운영자가 자주 반복하는 접속 절차를 짧게 줄여주는 실용적인 예시라고 볼 수 있습니다.

특히 점프 서버, 환경별 대상 서버, 키 파일, 접속 옵션을 하나로 묶어두었다는 점에서
반복 접속 업무를 단순화하는 용도로 이해하면 가장 자연스럽습니다.