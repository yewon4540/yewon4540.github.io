---
title: nvidia-smi의 "CUDA Version"은 toolkit 버전이 아니다 (드라이버 caps와 toolkit 구분)
layout: default
parent: AI & 머신러닝
nav_order: 1
written_at: 2026-05-19
---

# nvidia-smi의 "CUDA Version"은 toolkit 버전이 아니다 (드라이버 caps와 toolkit 구분)

폐쇄망 RHEL 서버에서 LLM 추론 워크로드를 셋업하던 중,
`nvidia-smi`를 쳤더니 우상단에 `CUDA Version: 13.2`가 보였습니다.

그래서 당연히 `nvcc --version`을 치면 `13.2`가 나올 줄 알았는데,
`bash: nvcc: command not found`가 떨어졌습니다.

그 다음에 `/usr/local`을 봤더니 `cuda-13.0` 디렉토리만 있었습니다.

이 글은 그때 잠깐 헷갈렸던 부분과,
`nvidia-smi`의 "CUDA Version"이 정확히 무엇을 의미하는지를 정리한 기록입니다.

---

## 1. 발단

처음 본 화면은 이랬습니다.

```text
+-----------------------------------------------------------------------------+
| NVIDIA-SMI 565.xx     Driver Version: 565.xx     CUDA Version: 13.2         |
+-----------------------------------------------------------------------------+
```

우상단의 `CUDA Version: 13.2`만 보고 자연스럽게 추측했습니다.

> 이 서버에는 CUDA toolkit 13.2가 깔려 있다.

그런데 막상 toolkit을 써보려고 했더니 흐름이 어긋났습니다.

```bash
nvcc --version
```

```text
bash: nvcc: command not found
```

`nvcc`가 PATH에 안 잡혀 있었고,
`/usr/local`을 직접 들여다봤더니 다음과 같았습니다.

```bash
ls /usr/local | grep cuda
```

```text
cuda-13.0
```

`cuda-13.2`는 어디에도 없었습니다.

여기서 잠깐 헷갈렸습니다.

> nvidia-smi는 분명히 13.2라고 말하는데,
> 실제로 깔린 toolkit은 13.0이다.
> 둘은 같은 게 아닌가?

---

## 2. nvidia-smi의 "CUDA Version"이 의미하는 것

검색하고 문서를 다시 읽어보니, 결국 같은 결론으로 모입니다.

`nvidia-smi`가 출력하는 `CUDA Version`은 **현재 깔린 NVIDIA 드라이버가 지원할 수 있는 CUDA API의 최대 버전**입니다.
즉 **호환 상한선**이지, 실제로 깔린 toolkit이 무엇인지를 알려주는 값이 아닙니다.

조금 더 풀어서 정리하면 이렇습니다.

| 값 | 정확한 의미 |
| --- | --- |
| `nvidia-smi` 우상단 `CUDA Version` | 드라이버가 지원 가능한 toolkit의 최대 버전 (드라이버 caps) |
| `nvcc --version` | PATH에 잡힌 CUDA toolkit의 실제 버전 |
| `/usr/local/cuda-X.Y/` | 디스크에 실제로 설치된 toolkit 디렉토리 |
| `/usr/local/cuda` (symlink) | 시스템 기본 toolkit으로 잡혀 있는 대상 |

표로 적고 나니 의외로 단순했는데,
처음에는 "드라이버 화면에 큼지막하게 적혀 있으니 그게 곧 toolkit이겠지"라고 자연스럽게 묶어서 봤던 게 함정이었습니다.

특히 드라이버만 깔린 서버에서도 `nvidia-smi`는 그 숫자를 보여주기 때문에,
**toolkit이 설치되어 있지 않아도** 우상단에는 값이 찍힙니다.

---

## 3. 실제 toolkit 버전을 확인하는 방법

같은 혼란을 다음에 또 만나지 않도록, 확인 절차를 한 줄씩 정리해뒀습니다.

### 3-1. PATH에 잡힌 toolkit

```bash
which nvcc
nvcc --version
```

PATH가 비어 있다면 toolkit 자체는 깔려 있어도 셸이 못 찾는 상태입니다.
이 경우 다음 단계로 넘어가 디렉토리부터 봅니다.

### 3-2. 설치된 toolkit 디렉토리

```bash
ls /usr/local | grep cuda
ls -la /usr/local/cuda 2>/dev/null
readlink -f /usr/local/cuda
```

- `cuda-13.0`, `cuda-12.4` 처럼 버전별 디렉토리가 보이면 그 버전이 실제로 깔린 것
- `/usr/local/cuda` symlink가 어느 디렉토리를 가리키는지가 "시스템 기본"

여러 toolkit이 공존하는 서버에서는 symlink가 기본 toolkit을 결정합니다.

### 3-3. 디렉토리별 정확한 버전

```bash
cat /usr/local/cuda-13.0/version.json
```

```json
{
  "cuda" : { "name" : "CUDA SDK", "version" : "13.0.x" },
  "cuda_nvcc" : { "version" : "13.0.x" }
}
```

`version.json`은 각 toolkit 디렉토리 안에 들어 있어서,
디렉토리 이름이 거짓말을 하는 경우(드물지만 가능)에도 정확한 값을 확인할 수 있습니다.

이 세 가지만 차례로 봐도 "현재 서버의 toolkit 상태"가 명확해집니다.

---

## 4. toolkit이 있는데 PATH에만 안 잡힌 경우

원래 상황으로 돌아오면,
서버에는 `cuda-13.0`이 깔려 있었고 다만 PATH가 잡혀 있지 않았을 뿐이었습니다.

`sudo` 권한이 없는 상황이라 시스템 전체에 손대지 않고, 본인 셸에만 toolkit을 활성화했습니다.

```bash
export CUDA_HOME=/usr/local/cuda-13.0
export PATH=$CUDA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH
```

확인은 다음과 같이 했습니다.

```bash
which nvcc
nvcc --version
```

```text
/usr/local/cuda-13.0/bin/nvcc
... release 13.0 ...
```

영구 적용은 `~/.bashrc` 끝에 위 세 줄을 추가하고 `source ~/.bashrc`만 해주면 됩니다.

이 방식의 장점은 단순합니다.

- `sudo` 권한 없이 가능
- 다른 사용자나 시스템 동작에 영향 없음
- 여러 toolkit이 공존해도 본인 셸에서만 원하는 버전을 골라 쓸 수 있음

여러 toolkit을 자주 갈아 끼우는 경우라면,
셸 함수로 묶어 두는 것도 편합니다.

---

## 5. PyTorch + CUDA 호환을 잠깐 짚고 가기

이번 셋업의 다음 단계는 PyTorch + vllm 류 LLM 워크로드였는데,
여기서도 한 번 더 헷갈렸던 부분이 있어서 같이 정리해 둡니다.

`import torch`로 GPU를 쓰는 데에는 **시스템 toolkit (`/usr/local/cuda-13.0`) 이 거의 사용되지 않습니다**.

이유는 단순합니다.

- PyTorch wheel(`torch+cu130` 등)은 **CUDA 런타임을 wheel 안에 함께 번들**합니다.
- 그래서 시스템 toolkit이 없어도, 드라이버만 호환되면 PyTorch는 GPU를 쓸 수 있습니다.

| 구성요소 | 역할 |
| --- | --- |
| NVIDIA 드라이버 | GPU ↔ 커널 사이를 연결. `nvidia-smi`의 "CUDA Version"이 이 드라이버의 caps |
| PyTorch wheel | 자체 번들된 CUDA 런타임으로 GPU 호출 |
| 시스템 toolkit (`/usr/local/cuda-X.Y`) | 커스텀 CUDA extension을 빌드할 때만 필요 |

즉, "단순 추론만 한다"면 시스템 toolkit은 사실상 옵션입니다.
반대로 **커스텀 CUDA extension을 빌드해서 써야 하는 경우**(`flash-attn` 같은 일부 라이브러리)에만 toolkit이 진짜 필요해집니다.

이걸 미리 알고 보면 `nvidia-smi`의 13.2와 시스템의 13.0 사이의 차이도 한 번 더 명확해집니다.

> 드라이버는 호환 상한을 표시할 뿐이고,
> 실제로 GPU 위에서 도는 코드의 CUDA 런타임은 보통 wheel이나 컨테이너가 함께 가지고 있다.

---

## 6. 짚어두고 싶은 것들

### 6-1. nvidia-smi의 우상단 숫자는 "상한선"

`nvidia-smi`를 처음 보는 사람은 우상단 `CUDA Version`을 "현재 설치된 toolkit"으로 읽기 쉽습니다.
그런데 그 자리는 **드라이버 caps의 표시**이고, 실제 toolkit과는 별도입니다.

이 한 줄을 기억해두면 같은 혼란을 반복하지 않습니다.

### 6-2. toolkit 확인은 세 군데서

- `which nvcc` → PATH 기준
- `/usr/local/cuda-X.Y/` 디렉토리 존재 여부
- `/usr/local/cuda` symlink가 가리키는 대상

이 세 가지를 차례로 보면, "이 서버에 toolkit이 있나? 있다면 어디에 있고 어떤 버전인가?"가 한 번에 정리됩니다.

### 6-3. sudo 없이 본인 셸에서 toolkit 골라 쓰기

`CUDA_HOME` + `PATH` + `LD_LIBRARY_PATH` 세 환경변수만 잡아주면,
다른 사용자/시스템에 영향 없이 본인 셸에서 toolkit을 활성화할 수 있습니다.

특히 다음 두 가지 환경에서 자주 쓰입니다.

- 여러 toolkit이 공존하는 공용 서버
- `sudo` 권한이 없는 운영 환경

### 6-4. 단순 추론이라면 시스템 toolkit이 없어도 된다

`pip install` 한 PyTorch wheel은 CUDA 런타임을 안에 가지고 있어서,
드라이버만 맞으면 GPU 추론은 잘 돌아갑니다.

시스템 toolkit이 진짜 필요한 시점은 보통 다음 두 가지입니다.

- 커스텀 CUDA extension을 직접 빌드해서 써야 할 때
- toolkit에 포함된 부속 도구(`cuda-gdb`, `nsight` 등)를 직접 사용할 때

처음 GPU 환경을 셋업하는 입장에서, 이 구분이 잡혀 있으면 의외로 시간이 많이 절약됩니다.

---

## 7. 마무리

처음 `nvidia-smi`의 13.2를 보고 toolkit을 13.2로 착각했을 때는,
"내가 모르는 사이에 13.2가 깔린 건가" 같은 잠깐의 혼란이 있었습니다.

그런데 한 줄씩 풀어보니 결론은 단순했습니다.

> 드라이버가 보여주는 숫자는 호환 상한이고,
> 실제 toolkit은 디렉토리와 `nvcc`가 답해준다.

이번 일을 정리하면서 GPU 셋업을 점검할 때 항상 짚고 가는 체크리스트가 짧게 잡혔습니다.

```text
nvidia-smi          → 드라이버 버전 / 호환 상한 (CUDA Version 컬럼)
which nvcc          → PATH에 잡힌 toolkit
ls /usr/local/cuda* → 실제 디스크에 깔린 toolkit
readlink -f /usr/local/cuda → 시스템 기본 toolkit symlink 대상
```

다음에 비슷한 환경을 만나도, 이 네 줄이면 5분 안에 toolkit 상태를 파악할 수 있을 것 같습니다.
