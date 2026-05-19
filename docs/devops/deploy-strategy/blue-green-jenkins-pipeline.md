---
title: Jenkins + Webhook + SSH Agent로 Blue-Green 배포 파이프라인 자동화
layout: default
parent: 배포 전략
grand_parent: Devops
nav_order: 3
written_at: 2026-05-19
---

# Jenkins + Webhook + SSH Agent로 Blue-Green 배포 파이프라인 자동화

[Docker Compose + Nginx reverse proxy로 만든 가장 단순한 Blue-Green 배포 구조] 글에서 구조를,
[Blue-Green 배포 스크립트 deploy.sh 분해] 글에서 배포 스크립트를 다뤘습니다.

이번 글은 시리즈의 마지막입니다.
손으로 `deploy.sh` 를 실행하는 단계까지 끌어올린 흐름을,
**GitHub push 한 번으로 끝까지 자동으로 굴러가도록** Jenkins 파이프라인을 잡은 기록입니다.

---

## 1. 발단

`deploy.sh` 까지 만들고 나서 한동안은 다음 흐름으로 배포했습니다.

```text
로컬에서 코드 변경 → GitHub push → 배포 서버에 SSH 접속 → git pull → bash deploy.sh
```

자동화가 절반쯤 끝난 상태라 운영 부담은 줄었지만,
"내가 직접 SSH 접속해서 명령을 치는" 단계가 남아 있었습니다.

이 단계까지 자동화하는 방향은 두 가지였습니다.

| 방향 | 의미 |
| --- | --- |
| GitHub Actions | 외부 러너에서 배포 서버로 SSH |
| **Jenkins** (선택) | 내부 Jenkins 가 Webhook 받아 배포 서버로 SSH |

이 환경은 사내 Jenkins 가 이미 떠 있었고,
Mattermost 같은 사내 알림 채널과 연동이 더 단순한 쪽이 Jenkins 라 두 번째를 골랐습니다.

---

## 2. 무엇을 자동화할 것인가

Jenkins 파이프라인이 책임지는 범위와 책임지지 않는 범위를 명확히 잘라뒀습니다.

| 책임 O | 책임 X |
| --- | --- |
| GitHub push 트리거 받기 (Webhook) | 코드 자체의 변경 검토 |
| 배포 서버 SSH 접속 | 배포 서버 부트스트래핑 / Docker 설치 |
| 배포 서버에서 git pull | 자체 build (deploy.sh 안에서 처리) |
| `deploy.sh` 호출 | Blue-Green 전환 로직 자체 (deploy.sh 안에 있음) |
| 결과를 Mattermost 로 알림 | 자체 트래픽 모니터링 / 롤백 |

핵심은 **Jenkins 가 deploy.sh 의 트리거 + 알림 단계까지만 담당** 한다는 점입니다.
Blue-Green 전환 로직 자체는 deploy.sh 안에 그대로 둡니다. 두 영역을 섞지 않으면 디버깅이 단순해집니다.

---

## 3. 파이프라인 한눈에 보기

전체 파이프라인을 단계로 정리하면 이렇습니다.

```text
GitHub push
   ↓
GitHub Webhook → Jenkins
   ↓
[stage 1] Deploy to Flask Server
   - SSH Agent credential 로 배포 서버 접속
   - 배포 서버에서 git pull origin main
   - 배포 서버에서 deploy.sh 실행
   ↓
[stage 2] Notify to Mattermost
   - 결과(SUCCESS/FAILURE) 에 따라 메시지 분기
   - Mattermost incoming webhook 으로 전송
```

두 stage 만 있는 단순한 구조지만,
이 안에 SSH credential 관리 / 실패 처리 / 알림 분기까지 들어 있습니다.

---

## 4. Jenkinsfile — 전체

전체 파이프라인 코드는 다음과 같습니다.
declarative pipeline 문법으로 작성했습니다.

```groovy
pipeline {
  agent any

  environment {
    FLASK_SERVER = "ubuntu@<deploy-server-ip>"
    PROJECT_DIR  = "/home/ubuntu/random_draw"
  }

  stages {
    stage('Deploy to Flask Server') {
      steps {
        script {
          try {
            sshagent (credentials: ['credential_key']) {
              sh """
                ssh -o StrictHostKeyChecking=no $FLASK_SERVER '
                  cd $PROJECT_DIR &&
                  git pull origin main &&
                  sh deploy.sh
                '
              """
            }
            env.DEPLOY_RESULT = 'SUCCESS'
          } catch (e) {
            env.DEPLOY_RESULT = 'FAILURE'
            currentBuild.result = 'FAILURE'
          }
        }
      }
    }

    stage('Notify to Mattermost') {
      steps {
        withCredentials([string(credentialsId: 'mattermost_webhook_url', variable: 'MM_WEBHOOK')]) {
          script {
            def msg
            if (env.DEPLOY_RESULT == 'SUCCESS') {
              msg = "Jenkins 빌드 성공! 배포 완료"
            } else {
              msg = "Jenkins 빌드 실패. 확인이 필요합니다."
            }

            sh """
              curl -X POST -H "Content-Type: application/json" \\
              -d '{ "text": "${msg}", "username": "jenkins-bot" }' \\
              \$MM_WEBHOOK
            """
          }
        }
      }
    }
  }
}
```

이제 줄 단위로 의미를 풀어봅니다.

---

## 5. environment — 변수 한 곳에 모아두기

```groovy
environment {
  FLASK_SERVER = "ubuntu@<deploy-server-ip>"
  PROJECT_DIR  = "/home/ubuntu/random_draw"
}
```

배포 서버 주소와 프로젝트 경로를 파일 상단의 `environment` 블록에 모았습니다.

이렇게 두면 다음 이득이 있습니다.

- 서버 IP 가 바뀔 때 한 줄만 수정하면 됨
- 다른 stage 에서도 같은 변수 참조 가능
- 새 사람이 이 파일을 처음 볼 때 "어디로 배포되는지" 가 상단에서 즉시 보임

운영 스크립트의 변수는 가능하면 한 곳에 모아두는 게 좋습니다.

---

## 6. SSH Agent credential

```groovy
sshagent (credentials: ['credential_key']) {
  sh """
    ssh -o StrictHostKeyChecking=no $FLASK_SERVER '
      cd $PROJECT_DIR &&
      git pull origin main &&
      sh deploy.sh
    '
  """
}
```

`sshagent` 블록은 Jenkins SSH Agent 플러그인이 제공합니다.
사전에 Jenkins Credentials 에 SSH private key 를 `credential_key` 라는 ID 로 등록해 두면,
이 블록 안에서 자동으로 ssh agent 가 활성화됩니다.

Jenkinsfile 안에는 **private key 가 절대 들어가지 않습니다**.
Credentials ID 한 줄만 참조하는 형태라, 코드가 노출되어도 키가 같이 새지 않습니다.

`StrictHostKeyChecking=no` 는 첫 접속 시 known_hosts prompt 를 무시하는 옵션입니다.
배포 서버가 자주 재생성되는 환경에서는 편리하지만,
호스트 키 검증을 우회한다는 의미가 있어서 **운영 환경에서는 known_hosts 를 사전에 박아두는 패턴**으로 가는 게 더 안전합니다.

---

## 7. 단일 SSH 세션 안에서 한 번에 처리

```bash
ssh -o StrictHostKeyChecking=no $FLASK_SERVER '
  cd $PROJECT_DIR &&
  git pull origin main &&
  sh deploy.sh
'
```

세 명령을 한 SSH 세션 안에서 `&&` 로 연결한 형태입니다.

이렇게 두면 다음 이점이 있습니다.

- 한 줄이라도 실패하면 그 시점에 전체가 중단됨 (`&&` 의 의미)
- SSH 세션을 한 번만 맺어 오버헤드가 작음
- Jenkins 로그에 명령 흐름이 한 덩어리로 떨어져 가독성이 좋음

만약 `&&` 대신 `;` 로 연결하면 앞 명령이 실패해도 다음 명령이 계속 실행됩니다.
배포 같은 작업에서는 절대 피해야 하는 패턴입니다.

> 운영 스크립트의 명령 체이닝은 가능하면 `&&` 를 기본으로 두자.
> 한 단계 실패가 다음 단계로 번지지 않게 해주는 가장 단순한 안전망.

---

## 8. try/catch 로 실패도 알림까지 끌고 가기

```groovy
try {
  sshagent (...) { sh """ ... """ }
  env.DEPLOY_RESULT = 'SUCCESS'
} catch (e) {
  env.DEPLOY_RESULT = 'FAILURE'
  currentBuild.result = 'FAILURE'
}
```

declarative pipeline 에서는 어떤 stage 가 실패하면 기본적으로 그 시점에 파이프라인이 중단됩니다.

그런데 이 파이프라인은 **성공이든 실패든 Mattermost 로 결과 알림이 가야 합니다**.
실패 시점에 그대로 멈춰버리면 알림 stage 가 실행되지 않습니다.

그래서 다음 패턴으로 잡았습니다.

- `try/catch` 로 SSH 실행 결과를 잡아두고
- 결과를 `env.DEPLOY_RESULT` 에 저장
- `currentBuild.result = 'FAILURE'` 로 빌드 자체 결과는 실패로 표시
- 그래도 stage 는 끝까지 진행 → 다음 stage(Mattermost) 실행

이렇게 두면 **Jenkins UI 상의 빌드 결과는 정확히 실패로 표시되면서,
알림은 빠지지 않고 가는** 형태가 됩니다.

대안으로 declarative pipeline 의 `post { always { ... } }` 블록을 쓰는 방법도 있습니다.
다음에 같은 패턴을 다시 짠다면 그쪽이 더 깔끔할 것 같습니다.

---

## 9. Mattermost 알림 분기

```groovy
withCredentials([string(credentialsId: 'mattermost_webhook_url', variable: 'MM_WEBHOOK')]) {
  script {
    def msg
    if (env.DEPLOY_RESULT == 'SUCCESS') {
      msg = "Jenkins 빌드 성공! 배포 완료"
    } else {
      msg = "Jenkins 빌드 실패. 확인이 필요합니다."
    }

    sh """
      curl -X POST -H "Content-Type: application/json" \\
      -d '{ "text": "${msg}", "username": "jenkins-bot" }' \\
      \$MM_WEBHOOK
    """
  }
}
```

Mattermost 의 incoming webhook URL 도 Jenkins Credentials 에 별도 등록해서,
파이프라인 코드에는 URL 이 노출되지 않게 했습니다.

`withCredentials` 블록 안에서는 환경 변수(`$MM_WEBHOOK`) 형태로 사용할 수 있고,
**Jenkins 로그에 출력될 때 자동으로 마스킹** 됩니다.

`def msg` 에서 결과에 따라 메시지를 분기하고,
한 줄짜리 `curl` 로 POST 합니다.

webhook URL 자체는 알려지면 누구나 메시지를 보낼 수 있어서 (사실상 secret),
Credentials 로 보관하는 게 기본 패턴입니다.

---

## 10. GitHub Webhook 연동

Jenkins job 의 트리거 설정에서 다음 둘을 활성화합니다.

- **GitHub project URL** 등록 — 해당 레포의 webhook 을 받을 준비
- **Build Triggers → GitHub hook trigger for GITScm polling** 체크

그리고 GitHub 레포의 Settings → Webhooks 에 Jenkins 의 webhook URL 을 등록합니다.

```text
https://<jenkins-host>/github-webhook/
```

이렇게 두면 GitHub push → Jenkins job 자동 실행 흐름이 완성됩니다.

직접 SCM polling 하는 방식보다 webhook 쪽이 다음 이유로 좋습니다.

- push 직후 즉시 트리거 (polling 지연 없음)
- Jenkins 가 GitHub 를 주기적으로 호출하지 않아 부하 적음

---

## 11. 짚어두고 싶은 것들

### 11-1. Credentials 는 코드 밖

SSH private key, Mattermost webhook URL — 둘 다 Jenkinsfile 안에 절대 박지 않았습니다.
Credentials 로 분리해두면 다음 이점이 모입니다.

- 코드가 노출되어도 secret 은 같이 새지 않음
- 키 갱신 시 코드 수정 없이 Credentials 만 교체
- Jenkins 로그에서 자동 마스킹

운영 파이프라인에서 가장 먼저 확인할 항목 중 하나입니다.

### 11-2. SSH 세션 안에서 `&&` 로 묶기

여러 명령을 한 줄로 묶을 때 `;` 대신 `&&` 를 쓰는 게 기본입니다.
한 단계 실패가 다음 단계로 번지지 않게 막아주는 가장 단순한 안전망입니다.

### 11-3. 실패도 알림까지 끌고 가기

배포 알림은 **성공보다 실패 때 더 중요**합니다.
실패 시 stage 가 끝나버려서 알림이 안 가는 패턴은 운영상 가장 피하고 싶은 모양입니다.

이 파이프라인은 try/catch 로 처리했지만,
다음에 다시 짠다면 declarative pipeline 의 `post { always { ... } }` 패턴이 더 깔끔할 것 같습니다.

```groovy
post {
  success { ... 성공 알림 ... }
  failure { ... 실패 알림 ... }
  always  { ... 공통 정리 ... }
}
```

### 11-4. Jenkins 는 deploy.sh 의 트리거에만 집중

Blue-Green 전환 로직 자체를 Jenkins 파이프라인 안에 옮기지 않은 게 결과적으로 좋았습니다.

- deploy.sh 는 로컬에서도 같은 동작
- Jenkins 가 깨져도 SSH 만 되면 수동 배포 가능
- 두 레이어의 책임이 명확히 분리됨

Jenkins 와 배포 로직을 너무 얽어 두면, Jenkins 가 멈췄을 때 운영 자체가 막힐 수 있습니다.
Jenkins 는 트리거 + 알림에만 집중하게 두는 게 깔끔합니다.

### 11-5. `StrictHostKeyChecking=no` 는 편의 옵션, 운영은 known_hosts 사전 등록

`-o StrictHostKeyChecking=no` 는 첫 접속을 편하게 해주지만,
운영에서는 호스트 키 검증을 우회한다는 의미가 있습니다.

운영 환경이라면 다음 패턴이 더 안전합니다.

- Jenkins 서버에 배포 서버의 known_hosts 를 사전에 박아두기
- ssh 옵션에서 `StrictHostKeyChecking=yes` 로 잡기

이 토이 프로젝트는 학습 우선이라 `no` 로 두었지만, 실제 운영 파이프라인에서는 한 번 더 고민할 자리입니다.

---

## 12. 마무리

세 글에 걸쳐 정리한 흐름을 한 줄로 요약하면 이렇습니다.

> Compose 파일을 색상별로 분리해 두고,
> deploy.sh 로 활성 색상 판단부터 트래픽 전환까지 자동화한 뒤,
> Jenkins 가 그 deploy.sh 의 트리거 + 결과 알림만 담당한다.

각 레이어가 자기 책임만 가지고 있어서, 어디가 깨져도 다른 레이어는 그대로 동작합니다.

- Jenkins 가 멈춰도 SSH 로 수동 배포 가능
- deploy.sh 가 깨져도 docker compose 명령으로 수동 전환 가능
- Nginx 가 깨져도 컨테이너만 직접 호출해서 동작 확인 가능

> 자동화의 가치는 정상일 때만 동작하는 게 아니라,
> 한 레이어가 깨졌을 때도 다른 레이어가 그대로 살아 있는 데에 있다.

Blue-Green 시리즈는 여기서 마무리하고,
다음에는 같은 사고 방식으로 K8s 위에서의 무중단 배포(rolling update, traffic shifting) 도 비슷한 시리즈로 풀어보려고 합니다.
