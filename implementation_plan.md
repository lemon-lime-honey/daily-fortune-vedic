# 베다 점성술 기반 일일 운세 자동화 파이프라인 개발 계획

모든 개발 단계는 **구현 -> 테스트 -> 수정 -> 커밋**의 사이클로 진행합니다. 커밋은 독립적으로 동작하는 기능 단위로 나누며, 영문 메시지와 불릿포인트를 사용하는 Conventional Commit 스타일을 엄격히 적용합니다.

## 1. 기반 설정 및 인프라 구축

### 1-1. 환경변수 구성

- **구현**: `.env.example` 및 `.env` 파일을 생성하고 필수 키 세트를 정의합니다.
- **테스트**: 환경변수 로딩 스크립트를 통해 값 누락 여부를 검증합니다.
- **커밋**: `build: setup environment variables configuration`

### 1-2. 도커 오케스트레이션 설계

- **구현**: `docker-compose.yml` 및 각 서비스의 Dockerfile을 작성하여 내부 네트워크를 묶습니다.
- **테스트**: `docker-compose up`을 실행하여 두 컨테이너 구동 상태와 네트워크 연결성을 검증합니다.
- **커밋**: `build: configure docker orchestration and network`

## 2. calc 서비스 개발 (Rust/Axum)

### 2-1. API 서버 스캐폴딩

- **구현**: Axum 기반의 기본 HTTP 서버와 POST 엔드포인트를 구축합니다.
- **테스트**: curl 명령어로 요청을 전송하여 HTTP 200 상태 코드를 확인합니다.
- **커밋**: `feat(calc): initialize axum http server and post endpoint`

### 2-2. 점성술 라이브러리 연동

- **구현**: 수신한 데이터를 파싱하고 vedaksha 라이브러리를 활용해 차트 계산 로직을 연결합니다.
- **테스트**: Rust 단위 테스트를 작성하여 행성 위치 및 다샤 계산 결과의 정확성을 검증합니다.
- **커밋**: `feat(calc): integrate vedaksha library for chart calculation`

### 2-3. 에러 핸들링 고도화

- **구현**: 잘못된 입력값 처리 및 예외 상황에 대한 JSON 에러 응답 규격을 정의합니다.
- **테스트**: 의도적으로 잘못된 데이터를 주입하여 에러 코드와 메시지가 제대로 반환되는지 확인합니다.
- **커밋**: `feat(calc): implement robust error handling and json response formatting`

## 3. api 서비스 개발 (Elixir)

### 3-1. Elixir 프로젝트 구성 및 HTTP 클라이언트

- **구현**: Mix 프로젝트를 생성하고 calc API 호출용 전용 클라이언트 모듈을 작성합니다.
- **테스트**: calc 서비스에 요청을 보내 JSON 응답 데이터 파싱 성공 여부를 확인합니다.
- **커밋**: `feat(api): add http client for calc service communication`

### 3-2. LLM 연동 및 프롬프트 생성기

- **구현**: 점성술 데이터를 조합하여 운세 해석을 지시하는 프롬프트를 구성하고 Gemma-4 API를 호출합니다.
- **테스트**: 더미 데이터를 활용해 LLM 호출을 시뮬레이션하고 자연어 응답 품질을 점검합니다.
- **커밋**: `feat(api): implement prompt builder and llm integration`

### 3-3. Notion 연동 클라이언트

- **구현**: 텍스트를 Notion 페이지나 데이터베이스로 전송하는 API 연동 모듈을 작성합니다.
- **테스트**: 샌드박스 공간에 테스트 문서 업로드 성공 여부를 확인합니다.
- **커밋**: `feat(api): add notion api client for text upload`

### 3-4. 장애 복구 및 스케줄러 통합

- **구현**: 한계점이 있는 백오프 재시도 로직과 주기적 실행을 위한 작업 스케줄러를 추가합니다.
- **테스트**: 강제로 지연을 발생시켜 재시도 로직이 올바르게 동작하는지 테스트합니다.
- **커밋**: `feat(api): implement retry policy and task scheduling`

## 4. 전체 파이프라인 통합 및 검증

### 4-1. 엔드투엔드 통합 테스트

- **구현**: 모든 컨테이너를 재빌드하고 스케줄러를 가동시켜 전체 워크플로우를 연동합니다.
- **테스트**: 데이터 추출부터 최종 노션 업로드까지의 흐름이 정상적으로 이어지는지 시스템 로그로 확인합니다.
- **커밋**: `test: verify end-to-end automated pipeline`
