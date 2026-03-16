# Yewon's Tech Blog

Cloud, DevOps, 인프라, AI & 머신러닝 기술 블로그입니다.

🔗 **블로그 주소:** [https://yewon4540.github.io](https://yewon4540.github.io)

## 카테고리

- **Kubernetes** — k3s
- **K-Digital Training**
- **인프라** — Cloud, Docker, 아키텍처, Server
- **Devops** — Nexus, Jenkins
- **모니터링** — Fluent
- **QA** — 성능테스트
- **AI & 머신러닝**
- **커리어&포트폴리오**

## 로컬 실행

```bash
bundle install
bundle exec jekyll serve
# → http://localhost:4000
```

## 로컬 관리자 화면 사용

공개 사이트의 `/admin`은 보안을 위해 비활성화되어 있습니다.

로컬에서만 관리자 화면을 사용합니다.

```bash
bash scripts/start-local-admin.sh
```

- 블로그: http://localhost:4000
- 관리자: http://localhost:4000/admin

관리자 화면에서는 카테고리별 글 작성, 수정, 태그 입력을 할 수 있습니다.

## 기술 스택

- [Jekyll](https://jekyllrb.com)
- [Just the Docs](https://just-the-docs.github.io/just-the-docs/) 테마
- [GitHub Pages](https://docs.github.com/en/pages)
