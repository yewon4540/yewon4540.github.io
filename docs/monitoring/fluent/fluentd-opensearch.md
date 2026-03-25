---
title: Kubernetes 환경에서 Fluentd + OpenSearch 로그 수집 구축
layout: default
parent: Fluent
grand_parent: 모니터링
nav_order: 1
written_at: 2026-03-25
---

# Kubernetes 환경에서 Fluentd + OpenSearch 로그 수집 구축

## 개요

Kubernetes 환경에서 발생하는 로그를 수집하고, 이를 OpenSearch에 저장하여 검색/분석하는 로그 파이프라인을 구축해보겠습니다.

구성 요소:

- Fluentd: 로그 수집 및 전달
- OpenSearch: 로그 저장 및 검색
- Kubernetes: 로그 발생 환경

---

## 아키텍처

```text
[Pod Logs] → [Fluentd] → [OpenSearch]
```

- Fluentd가 Pod 로그를 수집하고 OpenSearch로 전달
- 컨테이너 로그(`/var/log/containers/*.log`) 수집
- OpenSearch로 전달

---

## 사전 준비

- Kubernetes Cluster
- kubectl
- OpenSearch

---

## 1. OpenSearch 실행

```yaml
version: '3'
services:
  opensearch:
    image: opensearchproject/opensearch:2.11.0
    environment:
      - discovery.type=single-node
      - plugins.security.disabled=true
    ports:
      - "9200:9200"
```

```bash
docker-compose up -d
```

```bash
curl http://localhost:9200
```

---

## 2. Fluentd ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluentd-config
  namespace: logging
data:
  fluentd.conf: |
    <source>
      @type tail
      path /var/log/containers/*.log
      pos_file /fluentd/log/containers.log.pos
      tag kube.*
      <parse>
        @type json
      </parse>
    </source>

    <match kube.*>
      @type opensearch
      host opensearch.logging.svc.cluster.local
      port 9200
      scheme http
      logstash_format true
      logstash_prefix kube-logs
      include_tag_key true
      tag_key @log_name
      <buffer>
        flush_interval 10s
        retry_forever true
      </buffer>
    </match>
```

---

## 3. Fluentd Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fluentd
  namespace: logging
  labels:
    app: fluentd
spec:
  replicas: 1
  selector:
    matchLabels:
      app: fluentd
  template:
    metadata:
      labels:
        app: fluentd
    spec:
      containers:
      - name: fluentd
        image: fluent/fluentd-kubernetes-daemonset:v1.16-debian-opensearch-1
        volumeMounts:
        - name: varlogcontainers
          mountPath: /var/log/containers
          readOnly: true
        - name: config
          mountPath: /fluentd/etc/fluent.conf
          subPath: fluentd.conf
      volumes:
      - name: varlogcontainers
        hostPath:
          path: /var/log/containers
      - name: config
        configMap:
          name: fluentd-config
```

---

## 4. Namespace 생성

```bash
kubectl create namespace logging
```

---

## 5. 배포

```bash
kubectl apply -f fluentd-config.yaml
kubectl apply -f fluentd-deployment.yaml
```

---

## 로그 확인

```bash
curl http://<opensearch-ip>:9200/_cat/indices?v
```

```bash
curl http://<opensearch-ip>:9200/kube-logs/_search?pretty
```

---

## 설정 설명

### INPUT
- tail 기반 로그 수집
- `/var/log/containers/*.log`

### FILTER
- Kubernetes 메타데이터 추가

### OUTPUT
- OpenSearch로 로그 전송

---

## 트러블슈팅

### 로그 안 들어올 때

```bash
kubectl logs <fluentd-pod> -n logging
```

확인:
- OpenSearch 연결
- DNS
- 포트 (9200)

---

### 권한 문제

```yaml
securityContext:
  runAsUser: 0
```

---

## 확장 아이디어

- OpenSearch Dashboards 연동
- Index lifecycle 설정
- namespace별 로그 분리
- Kafka 중간 버퍼 추가

---

## 정리

Fluentd + OpenSearch 조합은:

- 가볍고 빠름
- Kubernetes 친화적
- 운영 환경에서 많이 사용됨

### 일괄 적용 (all-in-one)

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: logging

---
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluentd-config
  namespace: logging
  labels:
    k8s-app: fluentd-logging
data:
  fluentd.conf: |
    <match fluent.**>
      type null
    </match>

    <source>
      @type tcp
      port 24220
      format json
      tag applog
    </source>

    <match applog>
      @type rewrite_tag_filter
      <rule>
        key project
        pattern ^(.+)$
        tag $1.${tag}
      </rule>
    </match>

    <match **applog**>
      @type copy
      <store>
        @type opensearch
        host 10.0.0.100
        port 9200
        scheme http

        user "#{ENV['FLUENT_ELASTICSEARCH_USER']}"
        password "#{ENV['FLUENT_ELASTICSEARCH_PASSWORD']}"

        logstash_format true
        logstash_prefix ${tag}
        logstash_dateformat %Y%m%d

        include_tag_key true
        tag_key @log_name

        <buffer>
          flush_thread_count "8"
          flush_interval "10s"
          chunk_limit_size "5M"
          queue_limit_length "512"
          retry_forever true
        </buffer>
      </store>
    </match>

---
apiVersion: v1
kind: Secret
metadata:
  name: opensearch-credentials
  namespace: logging
type: Opaque
stringData:
  username: 아이디
  password: 패스워드

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fluentd
  namespace: logging
  labels:
    k8s-app: fluentd-logging
spec:
  replicas: 1
  selector:
    matchLabels:
      k8s-app: fluentd-logging
  template:
    metadata:
      labels:
        k8s-app: fluentd-logging
    spec:
      containers:
      - name: fluentd
        image: fluent/fluentd-kubernetes-daemonset:v1.16-debian-opensearch-1

        env:
        - name: FLUENT_ELASTICSEARCH_USER
          valueFrom:
            secretKeyRef:
              name: opensearch-credentials
              key: username

        - name: FLUENT_ELASTICSEARCH_PASSWORD
          valueFrom:
            secretKeyRef:
              name: opensearch-credentials
              key: password

        - name: FLUENT_UID
          value: "0"

        ports:
        - name: fluentd-source
          containerPort: 24220

        resources:
          requests:
            cpu: 100m
            memory: 200Mi
          limits:
            memory: 400Mi

        volumeMounts:
        - name: config-volume
          mountPath: /fluentd/etc/fluent.conf
          subPath: fluentd.conf

      volumes:
      - name: config-volume
        configMap:
          name: fluentd-config

---
apiVersion: v1
kind: Service
metadata:
  name: fluentd-svc
  namespace: logging
  labels:
    k8s-app: fluentd-logging
spec:
  type: ClusterIP
  selector:
    k8s-app: fluentd-logging
  ports:
  - name: fluentd-source
    port: 24220
    targetPort: fluentd-source
```