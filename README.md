# Expense Tracker (지출 추적기)

한국 금융기관 명세서 자동 파싱 및 지출 관리 시스템

## 기능

- 🏦 6개 금융기관 지원 (신한카드, 하나카드, 토스뱅크, 토스페이, 카카오뱅크, 카카오페이)
- 📊 자동 카테고리 분류 (식비, 교통, 통신 등)
- 🔍 지출 조회 및 필터링 (연도/월/카테고리/금융기관)
- 📈 월별 지출 요약 및 분석
- 🔐 Google OAuth 인증
- 📱 반응형 웹 인터페이스 (모바일/태블릿/데스크톱 지원)

## 기술 스택

### 백엔드
- Python 3.13
- FastAPI (REST API)
- SQLite (데이터베이스)
- JWT 인증
- watchdog (파일 감시)

### 프론트엔드
- React 18 + TypeScript
- Ant Design (UI 컴포넌트)
- React Router v6 (라우팅)
- Axios (HTTP 클라이언트)
- Vite (빌드 도구)

### 테스트
- Playwright (E2E 테스트)
- pytest (백엔드 테스트)

## 설치 및 실행

### 사전 요구사항
- Node.js 18+ (프론트엔드)
- Python 3.13+ (백엔드)
- Google OAuth Client ID (Google Cloud Console에서 발급)

### 1. 백엔드 설정

```bash
# 가상환경 생성 및 활성화
python3 -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate

# 의존성 설치
pip install -r requirements.txt
pip install -r requirements-api.txt

# 환경변수 설정
cp .env.example .env
# .env 파일 편집: GOOGLE_CLIENT_ID, SECRET_KEY 설정

# 데이터베이스 마이그레이션
python3 -m src.db.migrate

# API 서버 실행
cd backend
uvicorn main:app --reload
```

백엔드 서버: http://localhost:8000
API 문서: http://localhost:8000/docs

### 2. 프론트엔드 설정

```bash
# 의존성 설치
cd frontend
npm install

# 환경변수 설정
cp .env.example .env
# .env 파일 편집: VITE_GOOGLE_CLIENT_ID, VITE_API_BASE_URL 설정

# 개발 서버 실행
npm run dev
```

프론트엔드 서버: http://localhost:5173

### 3. E2E 테스트 실행

```bash
cd frontend

# Playwright 브라우저 설치 (최초 1회)
npx playwright install

# 백엔드 서버가 실행 중인지 확인
# http://localhost:8000/health

# 테스트 실행
npm run test:e2e

# UI 모드로 테스트 (대화형)
npm run test:e2e -- --ui

# 특정 테스트 파일만 실행
npx playwright test tests/e2e/auth.spec.ts
```

## 사용 방법

### 1. 웹 인터페이스를 통한 사용

1. 프론트엔드 (http://localhost:5173) 접속
2. "Google로 로그인" 버튼 클릭
3. Google 계정으로 인증
4. 대시보드에서 지출 분석 확인
5. "지출 내역" 메뉴에서 상세 거래 조회
6. "파싱 세션" 메뉴에서 파일 처리 이력 확인

### 2. 자동 파일 파싱 (백그라운드)

```bash
# 파일 감시 시스템 실행 (별도 터미널)
python main.py
```

1. 금융기관에서 명세서 다운로드 (Excel/CSV)
2. `inbox/` 폴더에 파일 복사
3. 파일 감시 시스템이 자동으로 파싱
4. 웹에서 즉시 조회 가능
5. 처리된 파일은 `archive/`로 자동 이동

## 프로젝트 구조

```
expense-tracker/
├── backend/              # FastAPI 백엔드
│   ├── api/
│   │   ├── routes/      # API 엔드포인트
│   │   │   ├── auth.py       # 인증 (Google OAuth)
│   │   │   ├── transactions.py  # 지출 조회/필터링
│   │   │   ├── categories.py    # 카테고리 관리
│   │   │   └── parsing_sessions.py  # 파싱 이력
│   │   └── schemas.py   # Pydantic 모델
│   ├── core/            # 설정, 보안
│   │   ├── config.py    # 환경변수
│   │   └── security.py  # JWT, OAuth
│   └── main.py          # FastAPI 앱
├── frontend/            # React 프론트엔드
│   ├── src/
│   │   ├── components/  # React 컴포넌트
│   │   │   ├── auth/        # 인증 컴포넌트
│   │   │   ├── common/      # 공통 UI (ErrorBoundary, Card 등)
│   │   │   ├── layout/      # 레이아웃 (Sidebar, TopBar)
│   │   │   ├── parsing/     # 파싱 관련 컴포넌트
│   │   │   └── transactions/ # 지출 관련 컴포넌트
│   │   ├── pages/       # 페이지
│   │   │   ├── LandingPage.tsx    # 로그인 페이지
│   │   │   ├── Dashboard.tsx      # 대시보드
│   │   │   ├── Transactions.tsx   # 지출 내역
│   │   │   ├── ParsingSessions.tsx # 파싱 세션
│   │   │   └── Settings.tsx       # 설정
│   │   ├── contexts/    # AuthContext (사용자 상태)
│   │   ├── api/         # API 클라이언트
│   │   │   ├── client.ts    # Axios 설정
│   │   │   └── services.ts  # API 호출 함수
│   │   └── types/       # TypeScript 타입
│   └── tests/e2e/       # E2E 테스트
│       ├── auth.spec.ts              # 인증 테스트
│       ├── protected-routes.spec.ts  # 라우트 보호 테스트
│       ├── landing.spec.ts           # 랜딩 페이지 테스트
│       ├── transactions.spec.ts      # 지출 기능 테스트
│       └── parsing-sessions.spec.ts  # 파싱 기능 테스트
├── src/                 # 파싱 시스템 (백그라운드)
│   ├── parsers/         # 금융기관별 파서
│   │   ├── base.py            # 파서 기본 클래스
│   │   ├── hana_parser.py     # 하나카드
│   │   ├── shinhan_parser.py  # 신한카드
│   │   ├── toss_parser.py     # 토스뱅크/페이
│   │   └── kakao_parser.py    # 카카오뱅크/페이
│   ├── db/              # 데이터베이스 레이어
│   │   ├── database.py   # DB 연결
│   │   ├── models.py     # SQLAlchemy 모델
│   │   └── migrate.py    # 마이그레이션
│   ├── file_watcher.py  # 파일 감시자
│   ├── router.py        # 금융기관 식별
│   └── category_matcher.py  # 카테고리 분류
├── inbox/               # 명세서 입력 폴더
├── archive/             # 처리된 파일 보관
└── data/                # 데이터베이스 (SQLite)
```

## API 엔드포인트

### 인증
- `POST /api/auth/google` - Google OAuth 로그인
- `GET /api/auth/me` - 현재 사용자 정보

### 지출 내역
- `GET /api/transactions` - 지출 목록 조회 (필터링/정렬/페이징)
- `GET /api/transactions/summary` - 월별 지출 요약
- `GET /api/transactions/categories` - 카테고리 목록
- `GET /api/transactions/institutions` - 금융기관 목록

### 파싱 세션
- `GET /api/parsing-sessions` - 파싱 이력 조회
- `GET /api/parsing-sessions/{id}` - 파싱 세션 상세
- `POST /api/parsing-sessions/{id}/retry` - 실패 건 재시도

## 데이터 스키마

### Transaction (지출 내역)
- `id`: 거래 ID (자동 증가)
- `user_id`: 사용자 ID (외래 키)
- `date`: 거래 날짜 (yyyy-mm-dd)
- `merchant_name`: 거래처명
- `amount`: 금액 (정수)
- `category`: 카테고리 (식비, 교통, 통신 등)
- `institution`: 금융기관명 (신한카드, 하나카드 등)
- `parsing_session_id`: 파싱 세션 ID (외래 키)

### ParsingSession (파싱 세션)
- `id`: 세션 ID (자동 증가)
- `user_id`: 사용자 ID (외래 키)
- `filename`: 원본 파일명
- `institution`: 금융기관명
- `status`: 처리 상태 (success, error, processing)
- `transaction_count`: 처리된 거래 수
- `error_message`: 에러 메시지 (실패 시)
- `created_at`: 처리 시작 시간

### User (사용자)
- `id`: 사용자 ID (자동 증가)
- `email`: 이메일 (Google OAuth)
- `name`: 이름
- `picture`: 프로필 사진 URL
- `google_id`: Google 고유 ID

## 보안 고려사항

### 인증 및 권한
- Google OAuth 2.0을 통한 안전한 인증
- JWT 토큰 기반 세션 관리
- 모든 API 엔드포인트 인증 필요 (로그인 제외)
- 사용자별 데이터 격리 (다른 사용자 데이터 접근 불가)

### 데이터 보안
- 로컬 SQLite 데이터베이스 (네트워크 노출 없음)
- 명세서 파일 로컬 저장 (외부 전송 없음)
- API 에러 메시지에 민감 정보 노출 방지

### 환경변수 관리
- `.env` 파일로 민감 정보 관리 (Git 제외)
- `GOOGLE_CLIENT_ID`: Google OAuth 클라이언트 ID
- `SECRET_KEY`: JWT 서명 키 (충분히 긴 랜덤 문자열)

## 개발 가이드

### 새로운 금융기관 파서 추가

1. `src/parsers/`에 새 파서 클래스 생성 (예: `kb_parser.py`)
2. `StatementParser` 기본 클래스 상속
3. `parse(input_data)` 메서드 구현
4. `src/router.py`에 식별 키워드 추가
5. 샘플 명세서로 테스트

### 새로운 카테고리 추가

1. `src/category_matcher.py`에 키워드 추가
2. `frontend/src/theme.config.ts`에 색상 추가
3. 데이터베이스 마이그레이션 불필요 (문자열 필드)

### E2E 테스트 작성

```typescript
// frontend/tests/e2e/example.spec.ts
import { test, expect } from '@playwright/test';

test('새로운 기능 테스트', async ({ page }) => {
  // 로그인
  await page.goto('http://localhost:5173');

  // 테스트 시나리오 작성
  await expect(page.locator('h1')).toContainText('예상 텍스트');
});
```

### 프로덕션 빌드

```bash
# 프론트엔드 빌드
cd frontend
npm run build
# 결과: dist/ 폴더에 정적 파일 생성

# 백엔드 실행 (프로덕션)
cd backend
uvicorn main:app --host 0.0.0.0 --port 8000
```

## 문제 해결

### 백엔드 서버가 시작되지 않음
- Python 버전 확인: `python3 --version` (3.13 이상)
- 의존성 설치 확인: `pip list | grep fastapi`
- `.env` 파일 존재 및 내용 확인

### 프론트엔드 빌드 오류
- Node.js 버전 확인: `node --version` (18 이상)
- 의존성 재설치: `rm -rf node_modules package-lock.json && npm install`
- TypeScript 에러 확인: `npm run build`

### Google OAuth 로그인 실패
- Google Cloud Console에서 OAuth 클라이언트 설정 확인
- 승인된 리디렉션 URI 확인: `http://localhost:5173`
- 클라이언트 ID 환경변수 확인 (`.env` 파일)

### E2E 테스트 실패
- 백엔드 서버 실행 확인: `curl http://localhost:8000/health`
- Playwright 브라우저 설치: `npx playwright install`
- 테스트 디버깅: `npm run test:e2e -- --debug`

## 기여 가이드

개발에 참여하거나 기여하고 싶으시다면 `CLAUDE.md` 파일을 참고하세요. Claude Code와 함께 작업하는 방법이 자세히 설명되어 있습니다.

## 라이선스

MIT License

Copyright (c) 2026 Expense Tracker

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
