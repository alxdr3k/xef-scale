# Show Version

현재 레포의 버전 및 릴리즈 상태를 표시합니다.

## Steps

1. 현재 버전 확인 (현재 디렉토리 기준):
```bash
cat .release-please-manifest.json
```

2. 릴리즈 PR 확인:
```bash
gh pr list --search "release-please" --state open --json number,title
```

3. 최근 태그 확인:
```bash
git tag --sort=-v:refname | head -5
```

4. k8s 배포 버전 확인 (stg/prd):
```bash
KUBECONFIG=~/.kube/config-hetzner kubectl get deploy xef-scale-stg -n apps-stg -o jsonpath='{.spec.template.spec.containers[0].image}'
KUBECONFIG=~/.kube/config-hetzner kubectl get deploy xef-scale-prd -n apps-prd -o jsonpath='{.spec.template.spec.containers[0].image}'
```

5. ops manifest 버전 확인:
```bash
grep -A1 "newTag:" ~/ws/xeflabs/ops/apps/xef-scale/overlays/stg/kustomization.yaml
grep -A1 "newTag:" ~/ws/xeflabs/ops/apps/xef-scale/overlays/prd/kustomization.yaml
```

## Output Format

| Item | Value |
|------|-------|
| Current | 0.3.0 |
| Release PR | - |
| STG (manifest) | 0.3.0 |
| STG (live) | 0.3.0 |
| PRD (live) | latest |

## Notes

- release-please로 버전 관리
- STG/PRD 배포 버전도 함께 표시
- manifest와 live 버전이 다르면 배포 필요
