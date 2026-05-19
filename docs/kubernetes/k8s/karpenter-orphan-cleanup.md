---
title: Karpenter 컨트롤러를 지웠는데 노드 2개가 22일째 운영 트래픽을 받고 있었다
layout: default
parent: k8s
grand_parent: Kubernetes
nav_order: 5
written_at: 2026-05-19
---

# Karpenter 컨트롤러를 지웠는데 노드 2개가 22일째 운영 트래픽을 받고 있었다

운영 중인 EKS 클러스터에서 Karpenter 사용을 정리하고 매니지드 노드 그룹으로 일원화했던 적이 있습니다.
그렇게 마무리됐다고 생각하고 한참이 지난 어느 날, 노드 목록을 확인하다가
"이건 뭐지?" 싶은 노드 2개가 보였습니다.

이번 글에서는 그 노드들을 어떻게 회수했는지,
회수 과정에서 어떤 함정에 걸렸는지를 정리해보려고 합니다.

---

## 1. 발단

평소처럼 클러스터 노드 상태를 확인하다가,
노드 이름이 다른 매니지드 NG 노드들과 다르게 생긴 것 두 개가 눈에 띄었습니다.

```bash
kubectl get nodes -o wide
```

매니지드 노드 그룹에서 올린 노드들은 인스턴스 타입이 `m5.2xlarge`인데,
이 둘만 `m5.xlarge`였고 `AGE`가 무려 `22d`로 찍혀 있었습니다.

게다가 `kubectl describe node`로 들여다보니
운영 트래픽을 받는 파드들이 멀쩡히 올라가 있었습니다.

순간적으로 든 생각은 단순했습니다.

> 분명히 Karpenter는 정리한 걸로 알고 있었는데,
> 노드 2개가 22일째 그대로 돌면서 트래픽까지 받고 있다고?

---

## 2. 상황 파악

### 2-1. Karpenter는 진짜로 지워진 게 맞나?

먼저 Karpenter 컨트롤러 상태부터 다시 확인했습니다.

```bash
kubectl get pods -n karpenter
kubectl get deploy -n karpenter
```

결과는 예상대로 비어 있었습니다.
Helm release도 없었고, namespace 자체는 남아 있지만 안에 도는 파드가 없었습니다.

그런데 NodeClaim과 NodePool, EC2NodeClass 같은 CRD 리소스는 그대로 살아 있었습니다.

```bash
kubectl get nodeclaim
kubectl get nodepool
kubectl get ec2nodeclass
```

NodeClaim 두 개가 `default-xxxxx`, `default-yyyyy` 형태로 남아 있었고,
이 NodeClaim들이 가리키는 EC2 인스턴스가 바로 그 22일짜리 노드들이었습니다.

### 2-2. 왜 살아남은 걸까?

조금만 생각해보면 답은 단순했습니다.

- Karpenter 컨트롤러는 NodeClaim의 reconcile을 책임지는 주체
- 그런데 컨트롤러가 사라지면 NodeClaim/Node에 걸린 finalizer를 처리해줄 사람이 없어짐
- finalizer가 남아 있는 한 NodeClaim이 영원히 stuck 상태로 유지됨
- NodeClaim이 살아 있는 한, 그 안에서 만들어진 EC2 인스턴스도 정리되지 않음

즉, 컨트롤러만 빼면 nodepool/nodeclaim/실제 EC2까지 묶어서 "고아 상태"로 남아 있게 되는 구조였습니다.

별일 없이 22일이 흐른 셈인데, 그동안 이 노드들은 EKS 입장에서는 정상 노드로 인식되어
새 파드 스케줄링까지 받고 있었습니다.

### 2-3. 그냥 EC2 terminate부터 하면 안 되나?

제일 먼저 떠오른 건 단순한 방법이었습니다.

> AWS 콘솔에서 terminate-instances 한 번 치면 끝나지 않나?

그런데 노드 위에 올라가 있는 파드 목록을 보는 순간,
그 생각은 바로 접었습니다.

각 노드에서 다음과 같은 워크로드가 동작 중이었습니다.

| 노드 | 올라가 있던 주요 파드 |
| --- | --- |
| 노드 A | 운영 앱 (replicas=1), 게이트웨이 앱 (replicas=1), istio-ingressgateway 1개 |
| 노드 B | CNPG operator (replicas=1), istio-ingressgateway 1개, 일부 프론트/API 파드 |

특히 신경 쓰였던 건 두 가지였습니다.

- `replicas=1`인 운영 앱 두 개가 노드 A에 거주
- `istio-ingressgateway`가 전체 5개 중 2개를 각 노드에 하나씩 두고 있었고, PDB(PodDisruptionBudget)가 걸려 있지 않음

이 상태에서 두 노드를 동시에 잘라버리면
`istio-ingressgateway` 2개가 한 번에 빠지면서 외부 트래픽 일부가 실제로 끊길 가능성이 있었습니다.

결국 단순 terminate가 아니라,
**먼저 파드를 안전하게 다른 노드로 옮긴 뒤 한 노드씩 정리하는 절차**가 필요하다는 결론이 났습니다.

---

## 3. 흡수 가능한 매니지드 NG 확인

다음으로 본 건 노드를 비울 때 파드들이 갈 곳이 있는지였습니다.

매니지드 노드 그룹은 `m5.2xlarge` × 24대로 운영 중이었고,
실제 CPU/메모리 사용량은 여유가 있었습니다.

```bash
kubectl top nodes
kubectl describe nodes | grep -E "Allocatable|Allocated"
```

평균적으로 노드당 절반 가까이 비어 있었기 때문에,
`m5.xlarge` 두 대의 파드를 흡수하는 데에는 문제가 없어 보였습니다.

이 정도면 한 노드씩 drain해도 신규 노드 프로비저닝 없이 기존 NG가 받아준다는 판단이 섰습니다.

---

## 4. ArgoCD self-heal에 한 번 막힘

위험 항목 중에서 `replicas=1`로 떠 있는 운영 앱이 신경 쓰였습니다.

drain 도중 짧게라도 다운타임이 발생할 수 있어서,
일단 잠깐 `replicas=2`로 늘리고 두 번째 파드를 다른 노드에 띄운 뒤 drain하면 되겠다고 생각했습니다.

```bash
kubectl scale deploy app-core --replicas=2
```

그런데 명령이 먹히고 5초쯤 지나니까
파드 수가 다시 1로 되돌아갔습니다.

이 앱은 ArgoCD가 관리하고 있었고,
`syncPolicy.automated`로 self-heal이 켜진 상태였습니다.

결국 ArgoCD 입장에서는 "원래 repo의 manifest는 `replicas: 1`인데 클러스터가 `2`니까 다시 1로 되돌려야 한다"고 판단한 것이었습니다.

> repo가 진실의 원천(Source of Truth)인 환경에서는
> kubectl로 임시 스케일링하는 우회 자체가 무력화된다.

여기서 선택지는 두 가지였습니다.

1. ArgoCD `auto-sync`를 일시 OFF하고 임시로 늘렸다가 drain 후 원복
2. 짧은 다운타임(수십 초)을 수용하고 그냥 drain

이번에는 운영 영향이 크지 않은 시간대였고,
ArgoCD 설정을 임시로 바꾸는 것 자체가 변경 이력이 남는 작업이라 두 번째를 택했습니다.

---

## 5. 노드 한 대씩 비우기

이제 본 작업입니다.
한 번에 두 노드를 건드리지 않고, 한 대씩 처리했습니다.

### 5-1. drain 전 dry-run으로 미리 확인

```bash
kubectl cordon <node-name>

kubectl drain <node-name> \
  --ignore-daemonsets --delete-emptydir-data \
  --dry-run=server
```

`--dry-run=server`는 실제로 옮기지 않고 어떤 파드가 evict 대상이 되는지 미리 확인할 수 있어서,
운영 환경에서 drain 전에 꼭 한 번 돌려보는 편입니다.

여기서 PDB 위반이 발견되면 그 시점에 멈추고 대응을 잡을 수 있습니다.

### 5-2. 실제 drain

```bash
kubectl drain <node-name> \
  --ignore-daemonsets --delete-emptydir-data \
  --grace-period=60 --timeout=10m
```

- `--ignore-daemonsets`: DaemonSet 파드는 어차피 노드가 사라지면 함께 사라지므로 제외
- `--delete-emptydir-data`: emptyDir 볼륨이 있는 파드도 강제 evict
- `--grace-period=60`: 파드 종료까지 60초 여유
- `--timeout=10m`: 전체 drain 작업 10분 한도

drain이 끝난 뒤에는 노드 위에 DaemonSet 파드만 남고,
기존 워크로드들은 매니지드 NG의 다른 노드들로 모두 옮겨갔습니다.

같은 절차를 두 번째 노드에도 똑같이 진행했습니다.
`replicas=1` 앱은 짧은 시간 동안 새 노드에서 컨테이너가 다시 뜨는 동안 잠깐 비어 있었지만,
앞서 결정한 대로 운영상 허용 가능한 범위였습니다.

---

## 6. EC2 종료 + finalizer 정리

파드가 다 빠진 노드는 이제 안전하게 정리할 수 있습니다.

먼저 EC2 인스턴스를 종료했습니다.

```bash
aws ec2 terminate-instances \
  --region ap-northeast-2 \
  --instance-ids i-0aaaaaaaaaaaaaaaa i-0bbbbbbbbbbbbbbbb
```

이 시점에 한 가지 문제가 있었습니다.

`kubectl delete nodeclaim` 을 그냥 치면 NodeClaim이 사라지지 않고 멈춰 있었습니다.
앞서 짚었던 그 함정,
"Karpenter 컨트롤러가 없어서 finalizer를 처리해줄 사람이 없다"가 그대로 재현된 것입니다.

finalizer를 직접 비워주는 패치를 한 번씩 넣어주면 됩니다.

```bash
kubectl patch nodeclaim default-xxxxx \
  --type=merge -p '{"metadata":{"finalizers":[]}}'

kubectl patch nodeclaim default-yyyyy \
  --type=merge -p '{"metadata":{"finalizers":[]}}'

kubectl patch node <node-a> \
  --type=merge -p '{"metadata":{"finalizers":[]}}'

kubectl patch node <node-b> \
  --type=merge -p '{"metadata":{"finalizers":[]}}'
```

finalizer가 비워지면 그 뒤로는 보통 삭제가 정상적으로 떨어집니다.

```bash
kubectl delete nodeclaim default-xxxxx default-yyyyy
kubectl delete node <node-a> <node-b>
```

EKS의 cloud node controller가 EC2 상태를 감지하면 Node 오브젝트는 자동으로 정리되는 경우도 있어서,
실제로 delete가 NotFound로 떨어지는 경우도 함께 봤습니다.

---

## 7. 결과

최종적으로 다음과 같이 정리되었습니다.

- EC2 2대 `terminated`
- Kubernetes Node / NodeClaim 모두 삭제
- 매니지드 NG 노드들만 남은 정상 상태로 복귀
- 22일 동안 점유되어 있던 서브넷 IP 2개도 함께 회수

처음 노드 목록에서 이상한 두 줄을 본 게 시작이었는데,
정리하고 나니 결국 "고아가 된 NodeClaim과 그 아래 노드들을 사람이 손으로 reconcile해준 작업"이었던 셈입니다.

---

## 8. 짚어두고 싶은 것들

이번 일에서 다음 작업 때 잊지 말아야겠다고 느낀 점들입니다.

### 8-1. Karpenter는 컨트롤러만 지운다고 끝이 아니다

Karpenter를 정리할 때는 다음 순서를 함께 고려해야 했습니다.

1. NodePool / EC2NodeClass에서 신규 노드가 더 이상 만들어지지 않게 막기
2. 현재 떠 있는 NodeClaim에 매핑된 노드들을 drain하고 정리
3. 컨트롤러(Helm release)와 CRD 제거
4. 마지막으로 IAM 인스턴스 프로파일 등 부가 리소스 정리

이번처럼 컨트롤러부터 지워버리면, 그 위에서 자라고 있던 NodeClaim들이 finalizer를 들고 그대로 멈추게 됩니다.

### 8-2. ArgoCD self-heal 환경에서 임시 scale은 무력화된다

GitOps 환경에서는 클러스터를 직접 바꾸는 우회가 잘 통하지 않습니다.

- 진실의 원천이 repo이기 때문에, `kubectl scale`이나 `kubectl edit`은 잠깐 적용됐다가 바로 되돌아갑니다.
- 정말로 임시 증설이 필요하다면 ArgoCD app의 `auto-sync`를 일시 OFF하거나, repo에 임시 PR/브랜치로 반영하는 편이 안전합니다.

이건 운영 측면에서도 일관성을 지켜주는 동작이라 ArgoCD 잘못이 아니라,
오히려 "kubectl로 우회하지 말라"는 신호로 받아들이는 게 맞다고 느꼈습니다.

### 8-3. PDB 없는 분산 파드는 동시 drain 금지

이번에 가장 조마조마했던 게 `istio-ingressgateway` 였습니다.

- replicas는 충분히(5개) 분산되어 있었지만 PDB가 걸려 있지 않았음
- 운 나쁘게 두 노드를 동시에 drain하면 그 위의 ingressgateway 2개가 동시에 evict될 수 있음
- 결과적으로 한 노드씩 진행해서 큰 문제가 없었지만, **분산 파드에는 PDB부터 잡아두는 게 안전**

다음에 비슷한 작업을 할 때는 drain 전에 PDB가 있는지부터 먼저 확인하고,
없다면 임시로라도 만들어 두는 흐름으로 가야겠다고 정리했습니다.

### 8-4. dry-run은 운영에서 거의 무료에 가까운 안전장치

`kubectl drain --dry-run=server`는 실제로 옮기는 것 없이 어떤 파드가 evict 대상이 되는지를 보여줍니다.

- PDB 위반이 발견되면 그 자리에서 멈출 수 있음
- 어떤 파드가 다른 노드에 다시 떠야 하는지를 미리 알 수 있음
- 위험 신호를 한 번 더 거르는 안전장치 역할

운영 작업에서는 dry-run을 한 번 더 돌리는 비용이 거의 없으니,
"바로 칠 수 있는 명령이라도 한 번 dry-run으로 확인"을 습관으로 두는 편이 좋다고 느꼈습니다.

---

## 9. 마무리

처음 노드 목록에서 이질적인 두 줄을 봤을 때는 솔직히 좀 놀랐습니다.

> 지운 줄 알았던 컴포넌트의 흔적이, 운영 트래픽 위에서 22일이나 돌고 있었다.

다행히 다른 사고로 이어지진 않았지만,
"컨트롤러를 지웠다 = 모든 게 정리됐다"는 가정이 얼마나 위험한지 다시 한 번 체감했습니다.

특히 finalizer는 평소엔 잘 보이지 않다가
컨트롤러가 없을 때 자기 존재감을 강하게 드러내는 항목이라,
앞으로는 컨트롤러 기반 컴포넌트를 들어내거나 옮길 때
"reconcile 주체가 사라진 뒤에 남는 리소스들이 무엇인지"를 먼저 정리해두려고 합니다.
