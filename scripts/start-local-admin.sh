#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v bundle >/dev/null 2>&1; then
  echo "bundle 명령을 찾을 수 없습니다. Ruby/Bundler를 먼저 설치해주세요."
  exit 1
fi

if ! command -v npx >/dev/null 2>&1; then
  echo "npx 명령을 찾을 수 없습니다. Node.js를 먼저 설치해주세요."
  exit 1
fi

echo "Jekyll 서버를 시작합니다..."
bundle exec jekyll serve --livereload &
JEKYLL_PID=$!

echo "Decap CMS 로컬 백엔드를 시작합니다..."
npx decap-server &
DECAP_PID=$!

cleanup() {
  echo "\n로컬 관리자 서버를 종료합니다..."
  kill "$JEKYLL_PID" "$DECAP_PID" 2>/dev/null || true
}

trap cleanup EXIT INT TERM

echo
echo "블로그: http://localhost:4000"
echo "관리자: http://localhost:4000/admin"
echo

wait
