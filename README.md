# Expense Tracker (지출 추적 앱)

한국 금융기관의 명세서를 자동으로 파싱하여 지출을 추적하는 로컬 파일 감시 시스템입니다.

## 개요

이메일 자동화나 웹 스크래핑 대신, 사용자가 수동으로 다운로드한 명세서를 지정 폴더에 넣으면 자동으로 분석하고 데이터를 추출하는 방식입니다.

## 지원 금융기관

- 신한카드
- 하나카드
- 토스뱅크
- 토스페이
- 카카오뱅크
- 카카오페이

> **참고**: 각 금융기관은 Open API를 통해 거래 데이터를 제공합니다. API 스펙은 프로젝트 문서 디렉토리(`docs/`)에서 확인하세요.

## 주요 기능

- 📂 **자동 파일 감시**: `inbox/` 디렉토리의 새 파일을 실시간 감지
- 🔍 **자동 금융기관 식별**: 파일 내용 기반으로 금융기관 자동 판별
- 📊 **통합 데이터 포맷**: 모든 금융기관의 거래내역을 하나의 형식으로 통합
- 🗂️ **자동 아카이빙**: 처리된 파일을 자동으로 `archive/` 폴더로 이동
- 📈 **카테고리 자동 분류**: 거래 내역을 식비, 교통, 통신 등으로 자동 분류

## 설치 방법

### 1. 필요 조건

- Python 3.8 이상
- pip 패키지 매니저

### 2. 의존성 설치

```bash
pip install -r requirements.txt
```

다음 라이브러리가 설치됩니다:
- `watchdog==3.0.0` - 파일 시스템 이벤트 모니터링
- `pandas==2.0.0` - 데이터 처리 및 분석
- `pdfplumber==0.9.0` - PDF 파싱
- `openpyxl==3.1.0` - Excel 파일 읽기/쓰기

### 3. 디렉토리 구조

다음 디렉토리들이 자동으로 생성됩니다:
- `inbox/` - 명세서 파일을 넣는 폴더
- `archive/` - 처리된 파일 저장
- `data/` - 통합 장부 CSV 파일
- `unknown/` - 식별 불가능한 파일
- `logs/` - 애플리케이션 로그

## 사용 방법

### 1. 프로그램 실행

```bash
python main.py
```

### 2. 명세서 추가

1. 금융기관 앱/웹사이트에서 명세서 다운로드 (Excel 또는 PDF)
2. 다운로드한 파일을 `inbox/` 폴더에 넣기
3. 자동으로 처리되고 결과가 `data/master_ledger.csv`에 저장됨

### 3. 결과 확인

```bash
cat data/master_ledger.csv
```

## 데이터 형식

통합 장부의 컬럼 구조:

| 컬럼 | 설명 | 형식 |
|------|------|------|
| 월 | 거래 월 | mm |
| 날짜 | 거래 날짜 | yyyy.mm.dd |
| 분류 | 카테고리 | 식비/편의점/교통/보험/기타 등 |
| 내역 | 거래처/상세 내용 | 텍스트 |
| 금액 | 거래 금액 | 정수 |
| 지출 위치 | 금융기관명 | 신한카드, 하나카드 등 |

## 설정

설정은 `src/config.py`에서 중앙 관리됩니다:
- 디렉토리 경로
- 금융기관 식별 키워드
- 카테고리 매칭 규칙

## 검증

설치가 올바르게 되었는지 확인:

```bash
# Python import 테스트
python -c "from src.config import DIRECTORIES, INSTITUTION_KEYWORDS, CATEGORY_RULES; print('Config loaded successfully')"

# 디렉토리 존재 확인
ls -la | grep -E "(src|tests|inbox|archive|data|unknown|logs)"
```

## 프로젝트 구조

```
expense-tracker/
├── main.py              # 메인 진입점
├── src/                 # 소스 코드
│   ├── config.py        # 설정
│   ├── models.py        # 데이터 모델
│   ├── file_watcher.py  # 파일 감시자
│   ├── router.py        # 금융기관 식별 라우터
│   ├── category_matcher.py  # 카테고리 매칭
│   ├── data_loader.py   # 데이터 로더
│   └── parsers/         # 금융기관별 파서
│       ├── base.py      # 파서 기본 클래스
│       └── hana_parser.py  # 하나카드 파서
├── tests/               # 테스트 코드
├── docs/                # 프로젝트 문서
├── inbox/               # 입력 폴더
├── archive/             # 보관 폴더
├── data/                # 통합 장부
├── logs/                # 로그 파일
└── unknown/             # 미식별 파일

```

## 기술 스택

이 프로젝트는 AI 에이전트를 활용한 개발에 최적화된 기술 스택을 사용합니다:

- **언어**: Python 3.8+
- **파일 감시**: watchdog
- **데이터 처리**: pandas
- **PDF 처리**: pdfplumber
- **Excel 처리**: openpyxl

## 개발 가이드

개발에 참여하거나 기여하고 싶으시다면 `CLAUDE.md` 파일을 참고하세요. Claude Code와 함께 작업하는 방법이 자세히 설명되어 있습니다.

## 라이선스

이 프로젝트는 개인 용도로 자유롭게 사용할 수 있습니다.
