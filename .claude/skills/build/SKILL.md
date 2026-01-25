---
name: build
description: Build and push Docker image for xef-scale Rails app
disable-model-invocation: true
argument-hint: [--push] [tag]
allowed-tools: Bash(docker:*), Bash(echo:*)
---

# Build xef-scale

Docker 이미지를 빌드합니다.

## 빌드

```bash
# 로컬 빌드
docker build -t xef-scale .

# 특정 태그
docker build -t ghcr.io/alxdr3k/xef-scale:<tag> .

# 멀티 플랫폼 빌드 (CI용)
docker buildx build --platform linux/amd64,linux/arm64 -t ghcr.io/alxdr3k/xef-scale:latest .

# 캐시 없이
docker build --no-cache -t xef-scale .
```

## 로컬 실행 테스트

```bash
docker run -p 3000:3000 --env-file .env xef-scale
docker run -d -p 3000:3000 --env-file .env --name xef-scale-test xef-scale
docker logs -f xef-scale-test
docker stop xef-scale-test && docker rm xef-scale-test
```

## ghcr.io 푸시

```bash
echo $GHCR_TOKEN | docker login ghcr.io -u alxdr3k --password-stdin
docker push ghcr.io/alxdr3k/xef-scale:<tag>
```
