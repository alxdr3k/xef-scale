# Sync Repo

현재 레포를 원격과 동기화합니다.

## Steps

1. 원격 브랜치 fetch:
```bash
git fetch --all --prune
```

2. main/dev 브랜치 업데이트:
```bash
# main 브랜치
git fetch origin main:main 2>/dev/null || echo "main: conflict or current branch"

# dev 브랜치
git fetch origin dev:dev 2>/dev/null || echo "dev: conflict or current branch"
```

3. 현재 브랜치가 main/dev면 pull --rebase:
```bash
current=$(git branch --show-current)
if [ "$current" = "main" ] || [ "$current" = "dev" ]; then
  git pull --rebase origin "$current"
fi
```

## Output Format

| Branch | Status |
|--------|--------|
| main | synced |
| dev | synced |
| current | dev |

## Notes

- `--prune`으로 삭제된 원격 브랜치 정리
- 충돌 발생 시 알림
