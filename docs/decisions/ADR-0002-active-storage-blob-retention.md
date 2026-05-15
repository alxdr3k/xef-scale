# ADR-0002: 업로드 이미지 blob은 ParsingSession 종결 후 180일 보존하고 그 이후 자동 purge한다

## Status

Accepted

## Date

2026-05-15

## Context

이미지 명세서 업로드는 `ProcessedFile.has_one_attached :file`을 통해 ActiveStorage blob으로 저장된다. 현재 라이프사이클은 다음과 같다.

1. 업로드: `ProcessedFile` + ActiveStorage attachment + blob 생성.
2. 파싱(`FileParsingJob` → `GeminiVisionParserService`): blob을 읽기만 한다.
3. 검토/`commit_all!`/`rollback_all!`/`discard_all!`: blob을 건드리지 않는다. `ProcessedFile`도 그대로 유지된다.
4. `ParsingSessionsController#destroy` (현재 `failed` 또는 `review_discarded`인 세션에만 허용): `ParsingSession`을 destroy하고 이어서 `processed_file&.destroy`를 호출 → 표준 `has_one_attached` 동작에 따라 attachment + blob이 purge된다.
5. `bulk_discard`: `discard_all!`만 호출하므로 blob은 살아남는다.

결과적으로 **정상 commit된 세션과 bulk_discard된 세션은 blob을 영구 보존**한다. 워크스페이스 하나가 매월 50장의 명세서 스크린샷(평균 2MB)을 업로드하면 1년에 약 1.2GB가 누적되며, 정리할 자동 경로가 없다.

원본 이미지의 가치는 시간에 따라 급격히 줄어든다.
- 파싱 정확도 디버깅에는 약 2~4주 내의 최근 데이터만 필요하다.
- 사용자가 "이 거래가 어디서 왔지?"를 확인하기 위해 원본 이미지를 다시 보는 빈도는 시간 경과에 따라 빠르게 0에 수렴한다.
- 영구 보존은 스토리지 비용과 개인정보 노출 면(외부 GCS/스토리지에 올라가는 명세서 사본)에서 부담이 된다.

## Decision

**`ParsingSession`이 종결 상태에 진입한 시점으로부터 180일 경과 시, 연결된 `ProcessedFile`의 attached blob을 자동으로 purge한다. `ProcessedFile` 레코드 메타데이터(`filename`, `byte_size`, `content_type`, `created_at`, `status`)는 그대로 유지한다.**

종결 상태 정의:
- `ParsingSession#status == "failed"`
- `ParsingSession#review_status ∈ {"committed", "rolled_back", "discarded"}`

180일 기준은 다음 시각 중 최신값을 사용한다.
- `committed_at`, `rolled_back_at`, `completed_at`(failed의 경우), 또는 review_status가 `discarded`로 변경된 시점.

`ParsingSessionsController#destroy`의 즉시 `ProcessedFile#destroy` 동작은 그대로 둔다 (사용자가 명시적으로 삭제한 경우).

## Consequences

긍정:
- 활성 워크스페이스의 ActiveStorage 누적이 약 6개월에서 plateau된다.
- 외부 스토리지에 보관되는 명세서 사본의 노출 기간이 명시적으로 제한된다.
- 사용자가 만든 `Transaction` 레코드는 영향받지 않는다. UI에서 원본 이미지 미리보기만 사라진다.

부정:
- 180일 이전 거래에 대한 "원본 이미지 보기"가 불가능해진다. UI는 blob이 사라진 경우를 인지하고 "원본 이미지가 보존 기간을 경과하여 삭제되었습니다"를 표시해야 한다.
- AI 파싱 오류를 사후 분석할 때 6개월보다 오래된 케이스는 디버깅 자료가 없다.

운영·테스트·문서 영향:
- 새 `ActiveStorageBlobCleanupJob`(daily, solid_queue cron)으로 구현한다. 본 ADR은 구현 PR을 강제하지 않는다 — 정책만 합의한다.
- `ProcessedFile`에 `blob_purged_at:datetime` 컬럼을 추가하면 UI에서 "원본 만료" 상태를 명확히 표현할 수 있다 (구현 시 함께 결정).
- `docs/context/current-state.md`의 "Needs audit"에서 본 항목을 제거하고 ADR로 링크한다.
- `docs/operations.md`의 운영 섹션에 "blob 보존 정책: 종결 + 180일" 한 줄 추가.

## 재검토 트리거

다음 중 하나라도 발생하면 본 ADR을 supersede한다.
1. ActiveStorage 누적 byte_size가 워크스페이스 평균 **2GB**를 초과 → 180일을 90일로 단축.
2. 사용자/오너 요청으로 "30일 후 즉시 삭제"가 기본값이어야 한다는 합의 발생.
3. 법적·계약상 보존 의무가 명시되어 더 긴 기간이 필요해질 때.

## Alternatives considered

- **commit 직후 즉시 purge** — 가장 적극적. 거부 이유: 사용자가 검토 직후 "방금 본 화면을 다시 보고 싶다"는 짧은 꼬리 수요가 있어 0일 보존은 UX를 해친다.
- **무기한 보존 (현 상태 유지)** — 결정을 미루는 안. 거부 이유: 자동 plateau가 없는 스토리지 모델은 운영 부채가 누적되며, 외부 스토리지 노출 면도 제한할 근거가 사라진다.
- **30일 / 90일 보존** — 더 짧은 TTL. 거부 이유: 디버깅·재현 비용이 갑자기 커진다. 운영 데이터로 측정 후 단축이 더 안전하다.
- **blob만 삭제하지 않고 `ProcessedFile` 전체 destroy** — 메타데이터까지 삭제. 거부 이유: `Transaction`이 `processed_file_id`를 참조하지 않지만 (현 스키마 기준), 향후 조인이 생길 가능성과 감사 추적성을 위해 메타데이터는 남긴다.

## Supersedes

없음.

## Superseded by

없음.
