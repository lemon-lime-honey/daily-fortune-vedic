# DAILY FORTUNE: VEDIC

> "직장 스트레스에 타로카드를 직접 섞어 다음날 운세를 확인하기 시작한 2025년 8월부터...
>
> 타로, 사주를 거쳐 마침내 베다 점성술(Vedic Astrology) 자동화에 이르기까지."

출생 차트와 당일 천체 배치 데이터를 결합하여 베다 점성술 기반 일일 운세를 계산하고, LLM을 통해 해석을 생성한 후 Notion에 매일 자동으로 기록하는 end-to-end 자동화 파이프라인입니다.

---

## 1. 시스템 아키텍처

전체 시스템은 점성술 연산 서비스(calc)와 파이프라인 제어 서비스(api)로 구성되며 Docker Compose 환경에서 동작합니다.

```txt
[ Scheduler / Trigger ]
           │
           ▼
┌─────────────────────────────────────────────────────────────┐
│  API Service (Elixir / OTP)                                 │
│  - Pipeline Orchestration & Fault Tolerance                 │
│  - Exponential Backoff & Retry Mechanism                    │
│                                                             │
│   1. Request Chart        2. Build Prompt & Interpret       │
│        │                          │                         │
│        ▼                          ▼                         │
│   ┌───────────────┐         ┌───────────────┐               │
│   │ Calc Service  │         │   LLM API     │               │
│   │ (Rust / Axum) │         │ (Gemini/Gemma)│               │
│   └───────────────┘         └───────────────┘               │
│                                   │                         │
│                           3. Upload Result                  │
│                                   │                         │
│                                   ▼                         │
│                             ┌───────────┐                   │
│                             │ Notion DB │                   │
│                             └───────────┘                   │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. 서비스 구성 및 기술 스택

### Calc Service (`calc/`)

천체 좌표 및 베다 점성술 차트 연산을 수행하는 Rust 기반 계산 서비스입니다.

- **Language & Framework**: Rust (2024 Edition), Axum 0.8
- **Core Library**: `vedaksha` (베다 점성술 연산 라이브러리)
- **Key Responsibilities**:
  - 출생 차트(Lagna/Ascendant) 및 달의 위치(Rashi, Nakshatra) 연산
  - 빔쇼타리 다샤(Vimshottari Dasha: Mahadasha, Antardasha) 주기 계산
  - 당일 행성 트랜짓(Transit) 좌표 및 하우스 위치 계산
  - JSON 규격 응답 및 `AppError` 기반 에러 처리

### API Service (`api/`)

연산 호출, LLM 해석, Notion 업로드 및 스케줄링을 총괄하는 Elixir 서비스입니다.

- **Language & Runtime**: Elixir 1.16+, Erlang/OTP
- **Key Libraries**: Req, Jason, Plug/Cowboy
- **Key Responsibilities**:
  - `FortuneService`: 연산, 프롬프트 빌드, LLM 호출, Notion 업로드 파이프라인 총괄
  - `PromptBuilder`: 행성 배치, 다샤, 트랜짓 데이터를 점성술 해석 전용 프롬프트로 변환
  - `LlmClient`: Gemini / Gemma API 연동 및 자연어 운세 생성
  - `NotionClient`: Notion 페이지 생성 및 운세 본문 블록 전송
  - `Scheduler`: 지정 시각 자동 실행 및 실패 시 재시도 제어

---

## 3. 환경 변수 설정

`.env.example` 파일을 복사하여 `.env` 파일을 생성하고 필수 값을 지정합니다.

```bash
cp .env.example .env
```

| 카테고리        | 환경 변수명         | 설명                                        | 기본/예시값        |
| :-------------- | :------------------ | :------------------------------------------ | :----------------- |
| **출생 정보**   | `BIRTH_DATE`        | 생년월일                                    | `YYYY-MM-DD`       |
|                 | `BIRTH_TIME`        | 태어난 시간                                 | `HH:MM:SS`         |
|                 | `BIRTH_LAT`         | 출생지 위도                                 | `37.5665`          |
|                 | `BIRTH_LON`         | 출생지 경도                                 | `126.9780`         |
|                 | `BIRTH_TZ_OFFSET`   | 출생지 표준시 오프셋                        | `9.0`              |
| **트랜짓 정보** | `TRANSIT_TIMEZONE`  | 기준 시간대                                 | `Asia/Seoul`       |
|                 | `TARGET_TZ_OFFSET`  | 목표 위치 표준시 오프셋                     | `9.0`              |
|                 | `TARGET_LATITUDE`   | 목표 위치 위도                              | `37.5665`          |
|                 | `TARGET_LONGITUDE`  | 목표 위치 경도                              | `126.9780`         |
|                 | `TARGET_HOUR`       | 운세 기준 시각 (시)                         | `12`               |
|                 | `TARGET_MINUTE`     | 운세 기준 시각 (분)                         | `0`                |
| **외부 API**    | `LLM_API_KEY`       | Google AI Studio API 키                     | `AIzaSy...`        |
|                 | `LLM_MODEL_NAME`    | 사용할 LLM 모델 식별자                      | `gemini-1.5-flash` |
|                 | `NOTION_API_KEY`    | Notion 통합 API 토큰                        | `secret_...`       |
|                 | `NOTION_TARGET_ID`  | 결과를 저장할 Notion 데이터베이스/페이지 ID | `32자리 UUID`      |
| **내부 통신**   | `RUST_CALC_API_URL` | Elixir가 호출할 Rust 계산 서비스 주소       | `http://calc:8080` |
|                 | `CALC_BIND_ADDR`    | Rust 서버 바인딩 주소                       | `0.0.0.0:8080`     |

환경 변수 정합성은 검증 스크립트로 사전 확인할 수 있습니다.

```bash
./verify_env.sh
```

---

## 4. 실행 및 배포

### Docker Compose 기반 통합 실행

Docker Compose를 통해 전체 서비스를 한 번에 빌드하고 백그라운드로 구동합니다.

```bash
# 컨테이너 빌드 및 구동
docker-compose up -d --build

# 로그 확인
docker-compose logs -f
```

### 개별 서비스 로컬 개발 및 테스트

#### Rust 계산 엔진 (`calc/`)

```bash
cd calc
cargo test
cargo run
```

#### Elixir 오케스트레이터 (`api/`)

```bash
cd api
mix deps.get
mix test
mix run --no-halt
```

---

## 5. 프로젝트 디렉터리 구조

```txt
daily-fortune-vedic/
├── .env.example          # 환경 변수 예제 템플릿
├── docker-compose.yml    # 멀티 컨테이너 오케스트레이션 정의
├── verify_env.sh         # 환경 변수 검증 쉘 스크립트
├── calc/                 # [Rust] 베다 점성술 계산 마이크로서비스
│   ├── Cargo.toml
│   ├── Dockerfile
│   └── src/
│       ├── main.rs       # Axum 서버 진입점
│       ├── handlers.rs   # 차트/다샤/트랜짓 연산 핸들러
│       └── models.rs     # 입출력 데이터 모델 및 에러 타입
└── api/                  # [Elixir] 파이프라인 오케스트레이션 서비스
    ├── mix.exs
    ├── Dockerfile
    ├── lib/
    │   └── api/
    │       ├── application.ex      # OTP 애플리케이션 수퍼바이저
    │       ├── calc_client.ex      # Calc 서비스 HTTP 클라이언트
    │       ├── fortune_service.ex  # 운세 생성 전체 흐름 파이프라인
    │       ├── llm_client.ex       # Gemini/Gemma LLM 연동 클라이언트
    │       ├── notion_client.ex    # Notion API 연동 클라이언트
    │       ├── prompt_builder.ex   # 점성술 데이터 프롬프트 생성기
    │       └── scheduler.ex        # 일일 작업 스케줄러 및 재시도 제어
    └── test/                       # 단위 및 통합 테스트
```
