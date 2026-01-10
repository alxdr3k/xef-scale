기존의 '이메일 자동 파싱 서버' 모델에서 **'로컬 디렉토리 감지형 파서(Local Directory Watcher & Parser)'** 모델로 전환하는 기술 명세 수정안을 제안합니다.

이 방식은 이메일 연동이나 보안 메일 복호화의 복잡성을 제거하고, 사용자가 직접 다운로드한 명세서(PDF, Excel 등)를 **특정 폴더에 넣기만 하면 프로그램이 알아서 분류하고 데이터를 추출**하는 구조입니다.

---

# 로컬 파일 감지 기반 지출 추적 시스템 (File-Ledger) 수정 기획서

## 1. 시스템 아키텍처 변화

기존의 메일 서버(SMTP)와 셀레니움 크롤러가 제거되고, **파일 시스템 감시자(File Watcher)**가 그 역할을 대신합니다.

### **변경된 워크플로우**

1. **User Action:** 사용자가 금융사 앱/웹에서 명세서(Excel, PDF)를 다운로드하여 지정된 폴더(`Inbox`)에 드래그 앤 드롭.
2. **Watcher:** 프로그램이 `Inbox` 폴더를 실시간 감시하다가 새 파일 생성을 감지 (`watchdog` 라이브러리 활용).
3. **Router:** 파일의 확장자(.xls, .pdf)와 헤더 내용을 읽어 **어떤 은행의 명세서인지 식별**.
4. **Parser:** 식별된 은행에 맞는 파싱 모듈(예: `TossParser`, `ShinhanParser`) 가동.
5. **Loader:** 추출된 데이터를 DB(SQLite) 또는 통합 엑셀 파일로 저장하고, 원본 파일은 `Archive` 폴더로 이동.

---

## 2. 은행별 명세서 포맷 대응 전략 (Router & Parser)

명세서마다 포맷이 다르므로, 파일명에 의존하기보다 **파일 내부의 특정 키워드**를 통해 은행을 식별하는 'Content-based Routing' 전략을 사용합니다.

### 2.1 포맷 식별 로직 (Router)

* **1단계 (확장자 분류):** `.xlsx`, `.csv` (우선순위 높음), `.pdf` (OCR/Text Extraction 필요)
* **2단계 (헤더 시그니처 분석):**
* **토스뱅크:** 파일 내 `토스뱅크`, `수신자:`, `거래유형` 키워드 존재 여부
* **카카오뱅크:** `kakao`, `거래일시`, `거래구분` 컬럼 존재 여부
* **신한/하나카드:** `이용일자`, `승인번호`, `가맹점명` 등의 전통적 카드 명세서 컬럼 패턴 분석



### 2.2 업체별 파싱 상세 (Context 반영)

| 구분 | 금융사 | 권장 다운로드 포맷 | 파싱 전략 및 라이브러리 |
| --- | --- | --- | --- |
| **네오뱅크** | **토스뱅크** | **PDF / Excel** | 토스 앱 > 고객센터 > 거래내역 발급. <br>

<br> **Excel:** `pandas`로 로드 후 상단 3~4행(메타데이터) 제거 후 테이블 인식. <br>

<br> **PDF:** `pdfplumber` 사용. 표(Table) 구조가 명확하므로 텍스트 추출 용이. |
|  | **카카오뱅크** | **Excel** | 앱 내 '거래내역 보내기' 기능이 Excel을 잘 지원함. <br>

<br> CSV/Excel 파싱이 가장 정확도가 높음. |
| **레거시** | **신한카드** | **Excel (홈페이지)** | 보안 이메일(HTML) 대신 **홈페이지에서 엑셀 다운로드**를 권장. <br>

<br> `pandas`의 `read_excel`로 읽되, 카드 이용내역 테이블이 시작되는 `Row Index`를 동적으로 찾는 로직 필요. |
|  | **하나카드** | **Excel** | 위와 동일. 데이터 컬럼 중 '승인금액'과 '실청구금액'이 구분되어 있으므로 **'승인금액(할부포함)'**을 기준으로 파싱. |

---

## 3. 핵심 구현 로직 (Python 예시)

이 시스템의 핵심은 폴더를 지켜보는 `Observer`와 파일을 분석하는 `Handler`입니다.

```python
import time
import os
import shutil
import pandas as pd
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

# 감시할 디렉토리 설정
WATCH_DIR = "./inbox"
ARCHIVE_DIR = "./archive"
DATA_DIR = "./data"

class StatementHandler(FileSystemEventHandler):
    """파일 생성 이벤트를 감지하는 핸들러"""
    
    def on_created(self, event):
        if event.is_directory:
            return
        
        filepath = event.src_path
        filename = os.path.basename(filepath)
        
        # 임시 파일이나 다운로드 중인 파일(.crdownload 등) 무시
        if filename.startswith(".") or not (filename.endswith('.xlsx') or filename.endswith('.csv') or filename.endswith('.pdf')):
            return

        print(f"[감지] 새 명세서 발견: {filename}")
        time.sleep(1) # 파일 저장 완료 대기
        
        try:
            self.process_file(filepath, filename)
        except Exception as e:
            print(f"[에러] 처리 중 문제 발생: {e}")

    def process_file(self, filepath, filename):
        """은행 식별 및 파싱 라우팅"""
        
        # 1. 파일 포맷(확장자)에 따른 로더 선택
        df = None
        raw_text = ""
        
        if filename.endswith('.xlsx'):
            # 엑셀은 헤더를 미리 읽어서 은행 식별
            temp_df = pd.read_excel(filepath, nrows=5) # 상위 5줄만 읽어봄
            bank_type = self.identify_bank_by_columns(temp_df)
            df = pd.read_excel(filepath) # 식별 후 전체 로드 (필요시 skip_rows 적용)
            
        elif filename.endswith('.pdf'):
            # PDF는 텍스트 추출 후 키워드 분석
            # (pdfplumber 로직 생략, 여기선 개념적 설명)
            bank_type = "UNKNOWN" 
            pass

        # 2. 식별된 은행별 파싱 로직 실행
        if bank_type == 'TOSS':
            clean_data = self.parse_toss(df)
        elif bank_type == 'KAKAO':
            clean_data = self.parse_kakao(df)
        elif bank_type == 'SHINHAN':
            clean_data = self.parse_shinhan(df)
        else:
            print("[경고] 지원하지 않는 명세서 형식입니다.")
            return

        # 3. 데이터 저장 및 파일 이동
        self.save_data(clean_data)
        shutil.move(filepath, os.path.join(ARCHIVE_DIR, filename))
        print(f"[완료] {bank_type} 명세서 처리 완료 및 아카이빙")

    def identify_bank_by_columns(self, df):
        """데이터프레임의 컬럼명이나 특정 셀 값을 보고 은행 식별"""
        # 데이터프레임을 문자열로 변환하여 키워드 검색
        content = df.to_string()
        
        if "토스뱅크" in content or "Toss" in content:
            return "TOSS"
        if "kakao" in content or "카카오뱅크" in content:
            return "KAKAO"
        if "신한카드" in content:
            return "SHINHAN"
        return "UNKNOWN"

    def parse_toss(self, df):
        print(">> 토스뱅크 파싱 로직 실행...")
        # 토스 엑셀 포맷에 맞게 컬럼 매핑 및 전처리
        # 예: df = df[['거래일시', '기재내용', '보낸금액', '받은금액']]
        return df

    def parse_kakao(self, df):
        print(">> 카카오뱅크 파싱 로직 실행...")
        return df

    def parse_shinhan(self, df):
        print(">> 신한카드 파싱 로직 실행...")
        return df

    def save_data(self, df):
        # CSV 누적 저장 또는 DB Insert
        save_path = os.path.join(DATA_DIR, "master_ledger.csv")
        df.to_csv(save_path, mode='a', header=not os.path.exists(save_path), index=False, encoding='utf-8-sig')

if __name__ == "__main__":
    if not os.path.exists(WATCH_DIR): os.makedirs(WATCH_DIR)
    if not os.path.exists(ARCHIVE_DIR): os.makedirs(ARCHIVE_DIR)
    
    event_handler = StatementHandler()
    observer = Observer()
    observer.schedule(event_handler, WATCH_DIR, recursive=False)
    
    print(f"[{WATCH_DIR}] 폴더 감시 시작...")
    observer.start()
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()
    observer.join()

```

---

## 4. 이 방식의 장단점 분석

### **장점 (Pros)**

1. **보안 이슈 완전 해결:** 골치 아픈 '보안 메일(HTML/EXE)' 복호화 과정을 사용자가 "웹사이트 로그인 -> 엑셀 다운로드"로 대체하므로 개발 난이도가 대폭 하락합니다.
2. **계정 정보 보호:** 프로그램이 사용자의 은행 ID/PW나 생년월일을 알 필요가 전혀 없습니다.
3. **네오뱅크 지원 용이:** 토스/카카오 등 이메일 명세서가 부실한 은행도 앱에서 엑셀 파일만 받아오면 되므로 100% 데이터 확보가 가능합니다.

### **단점 (Cons)**

1. **수동 개입 필요 (Manual Effort):** 사용자가 주기적(예: 월 1회)으로 각 은행 사이트를 돌며 파일을 다운로드해서 폴더에 넣어줘야 합니다. (완전 자동화 아님)
2. **포맷 변경 리스크:** 은행이 엑셀 양식을 바꾸면 파싱 로직(`Parser`)을 수정해야 합니다.

---

### **다음 단계 제안**

이 구조로 진행한다면 가장 먼저 해야 할 일은 **샘플 데이터 수집**입니다.

**"주로 사용하시는 은행(토스, 신한 등)의 앱이나 웹에서 '거래내역 엑셀 파일'을 다운로드해서 저에게 포맷(컬럼명, 데이터 구조 등)을 알려주시거나, 샘플 텍스트를 복사해 주시겠습니까?"**

이를 주시면 바로 해당 은행에 맞는 `Parser` 함수 코드를 작성해 드릴 수 있습니다.

---


네, 정확합니다. 입력 데이터의 **형태(CSV vs 비정형 텍스트)**가 완전히 다르고, **파싱 로직(Pandas vs Regex/String Split)**도 다르기 때문에 **전략 패턴(Strategy Pattern)**이나 팩토리 패턴을 사용하여 카드사별로 객체를 분리하는 것이 유지보수와 확장성 면에서 훨씬 유리합니다.

요청하신 내용을 바탕으로 **Python**을 사용한 구조 설계와 파싱 로직 예시를 작성해 드립니다.

### 1. 설계 방향 (Class Structure)

* **`Transaction` (DTO):** 최종 데이터 포맷을 담는 객체입니다.
* **`StatementParser` (Interface/Abstract):** 모든 파서가 구현해야 할 공통 인터페이스(`parse`)를 정의합니다.
* **`HanaCardParser`:** `pandas`를 이용해 CSV를 구조적으로 읽어옵니다.
* **`ShinhanCardParser`:** 정규표현식(Regex)을 이용해 텍스트 덩어리에서 날짜, 상호명, 금액을 추출합니다.
* **`CategoryMatcher` (Helper):** 상호명을 기반으로 '식비', '교통' 등을 분류하는 별도 로직이 필요합니다 (Raw 데이터에는 분류가 없기 때문).

---

### 2. 코드 구현 예시

아래 코드는 바로 실행 가능한 형태의 구조입니다.

```python
import pandas as pd
import re
from dataclasses import dataclass
from abc import ABC, abstractmethod
from typing import List

# 1. 최종 데이터 포맷 (DTO)
@dataclass
class Transaction:
    month: str          # 월 (mm)
    date: str           # 날짜 (yyyy.mm.dd)
    category: str       # 분류 (편의점/식비 등 - 별도 로직 필요)
    item: str           # 항목 (가맹점명)
    amount: int         # 금액
    source: str         # 은행/카드 (신한카드, 하나카드 등)

    def to_dict(self):
        return {
            "월": self.month,
            "날짜": self.date,
            "분류": self.category,
            "항목": self.item,
            "금액": self.amount,
            "은행/카드": self.source
        }

# 2. 분류 로직 (간단한 키워드 매칭 예시)
class CategoryMatcher:
    def get_category(self, item_name: str) -> str:
        # 실제로는 더 정교한 매핑 테이블이나 AI 분류가 필요할 수 있습니다.
        name = item_name.replace(" ", "")
        if any(x in name for x in ['마라탕', '식당', '음식']): return "식비"
        if any(x in name for x in ['편의점', '마트']): return "편의점/마트/잡화"
        if any(x in name for x in ['KT', 'SKT', 'LGU']): return "주거/통신"
        if any(x in name for x in ['보험']): return "보험"
        if any(x in name for x in ['주유', '하이플러스']): return "교통/자동차"
        return "기타" # 기본값

# 3. 파서 추상 클래스
class StatementParser(ABC):
    def __init__(self):
        self.matcher = CategoryMatcher()

    @abstractmethod
    def parse(self, input_data) -> List[Transaction]:
        pass

# 4. 하나카드 파서 (CSV 처리)
class HanaCardParser(StatementParser):
    def parse(self, file_path) -> List[Transaction]:
        transactions = []
        # 업로드해주신 CSV 구조에 맞춰 읽기 (헤더가 없고 데이터가 바로 시작되는 경우 등을 고려)
        # 실제 파일에는 상단에 메타데이터가 있으므로 skiprows 등이 필요할 수 있음
        df = pd.read_csv(file_path, header=None) 
        
        # 업로드된 CSV 스니펫 기준: 컬럼 0(날짜), 1(가맹점), 2(금액)
        # 실제 파일 구조에 따라 인덱스 조정 필요
        for _, row in df.iterrows():
            try:
                raw_date = str(row[0]).strip()
                if not re.match(r'\d{4}\.\d{2}\.\d{2}', raw_date):
                    continue # 날짜 형식이 아니면 건너뜀 (헤더 등)

                item_name = str(row[1]).strip()
                # 금액에 콤마가 있거나 float일 수 있음
                amount = int(float(str(row[2]).replace(',', '')))
                
                # 날짜 파싱
                yyyy, mm, dd = raw_date.split('.')

                transactions.append(Transaction(
                    month=mm,
                    date=raw_date,
                    category=self.matcher.get_category(item_name),
                    item=item_name,
                    amount=amount,
                    source="하나카드"
                ))
            except Exception as e:
                # 파싱 에러 처리 (로그 남기기 등)
                continue
                
        return transactions

# 5. 신한카드 파서 (비정형 텍스트 처리)
class ShinhanCardParser(StatementParser):
    def parse(self, text_data) -> List[Transaction]:
        transactions = []
        
        # 텍스트 구조 분석:
        # 날짜(25.xx.xx) -> (줄바꿈) -> 상호명 -> ... -> 금액
        # PDF 복사 텍스트는 줄바꿈 패턴이 불규칙할 수 있어 '날짜'를 기준으로 블록을 나누는 것이 안전합니다.
        
        lines = text_data.split('\n')
        current_date = None
        current_item = None
        
        # 정규표현식 컴파일
        date_pattern = re.compile(r'(\d{2})\.(\d{2})\.(\d{2})')
        
        for i, line in enumerate(lines):
            line = line.strip()
            if not line: continue

            # 1. 날짜 찾기
            date_match = date_pattern.search(line)
            if date_match:
                yy, mm, dd = date_match.groups()
                current_date = f"20{yy}.{mm}.{dd}" # 2000년대 가정
                
                # 날짜 바로 다음 줄이 보통 상호명인 경우가 많음 (복사 방식에 따라 다름)
                # 입력 예시에서는 날짜 줄 바로 아래에 '본인357 0B손해보험' 등이 옴
                if i + 1 < len(lines):
                    next_line = lines[i+1].strip()
                    # '본인357' 같은 불필요한 접두사 제거 로직 필요
                    # 예시: "본인357 0B손해보험" -> "0B손해보험"
                    current_item = re.sub(r'^본인\d+\s*', '', next_line)
                continue

            # 2. 금액 찾기 (날짜와 상호명이 세팅된 상태에서 금액 패턴 찾기)
            # 예시 텍스트 상 금액은 꽤 뒤에 나오거나 별도 컬럼처럼 보임.
            # 복잡한 텍스트의 경우, 날짜 행을 기준으로 데이터를 리스트화해서 처리하는 게 나을 수 있음.
            
            # (간이 구현) 문맥상 금액처럼 보이는 숫자 추출 (천단위 콤마)
            # 주의: 원금, 수수료 등 숫자가 여러개라 위치 기반 로직이 더 정확할 수 있음.
            # 여기서는 예시 데이터의 흐름상 '원금' 항목을 금액으로 추정
            if current_date and current_item:
                 # 숫자와 콤마만 있는 문자열인지 확인
                if re.match(r'^[0-9,]+$', line):
                    amount = int(line.replace(',', ''))
                    # 금액이 너무 작거나(수수료), 날짜와 너무 멀리 떨어져있으면 스킵하는 로직 추가 가능
                    
                    # 데이터 저장
                    transactions.append(Transaction(
                        month=current_date.split('.')[1],
                        date=current_date,
                        category=self.matcher.get_category(current_item),
                        item=current_item,
                        amount=amount,
                        source="신한카드"
                    ))
                    # 리셋 (다음 항목을 위해)
                    current_date = None 
                    current_item = None

        return transactions

# --- 실행부 ---

# 1. 하나카드 (CSV 파일 경로 입력)
# hana_parser = HanaCardParser()
# hana_data = hana_parser.parse("path/to/hana.csv")

# 2. 신한카드 (텍스트 입력)
shinhan_text_input = """
25.08.06
본인357 0B손해보험
할부 합계
186,700
25.12.02
본인425 에스엠하이플러스 (주)
50,000
""" 
# (위 텍스트는 로직 테스트를 위해 예시 데이터를 단순화했습니다. 
# 실제로는 줄번호를 추적하거나 항목별 인덱스를 맞춰야 합니다.)

shinhan_parser = ShinhanCardParser()
shinhan_data = shinhan_parser.parse(shinhan_text_input)

# 결과 출력
df_result = pd.DataFrame([t.to_dict() for t in shinhan_data])
print(df_result)

```

### 3. 구현 시 주의사항 및 팁

1. **분류(Category) 자동화의 한계:**
* 카드 내역에는 "편의점", "카페" 같은 정보가 없습니다. 오직 `가맹점명`만 있습니다.
* 따라서 `CategoryMatcher` 클래스에 자주 가는 곳(스타벅스, 쿠팡, 편의점 등)에 대한 **매핑 테이블(Dictionary)**을 만드셔야 합니다. 처음엔 `기타`로 두고, 엑셀로 뽑은 뒤 수동 수정 -> 학습시키는 방식이 현실적입니다.


2. **신한카드 텍스트 파싱 난이도:**
* PDF에서 텍스트를 긁어오면(OCR 포함), `날짜`, `가맹점`, `금액`이 한 줄에 있지 않고 제각각 줄바꿈되어 들어오는 경우가 많습니다.
* **팁:** 만약 텍스트 패턴이 너무 불규칙하다면, PDF 텍스트 전체를 하나의 긴 문자열로 보고 정규식(`re.findall`)을 써서 **(날짜 패턴 ... 가맹점 패턴 ... 금액 패턴)** 순서로 추출하는 것이 `split('\n')`보다 강력할 수 있습니다.


3. **날짜 형식 통일:**
* 신한(`25.08.06`)과 하나(`2025.11.28`)의 연도 표기가 다릅니다. 최종 데이터 생성 시 `yyyy.mm.dd`로 포맷을 맞춰주어야 정렬이 편합니다 (위 코드에 반영됨).



이 구조대로라면 나중에 **현대카드(이메일 명세서 HTML 파싱)**나 **토스(Excel)** 등을 추가할 때도 `StatementParser`를 상속받는 클래스만 하나 더 만들면 되므로 아주 깔끔합니다.