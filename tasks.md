# 프로젝트 할 일 목록

## 1. 기반 설정 및 인프라 구축

- [x] 1-1. 환경변수 구성 (`.env.example`, `.env`)
- [x] 1-2. 도커 오케스트레이션 설계 (`docker-compose.yml`, 각 서비스 Dockerfile)

## 2. calc 서비스 개발 (Rust/Axum)

- [x] 2-1. API 서버 스캐폴딩 (Axum HTTP POST 엔드포인트)
- [x] 2-2. 점성술 라이브러리 연동 (vedaksha 차트 계산 로직)
- [x] 2-3. 에러 핸들링 고도화 (JSON 응답 규격 적용)

## 3. api 서비스 개발 (Elixir)

- [x] 3-1. Elixir 프로젝트 구성 및 HTTP 클라이언트 (calc API 호출)
- [x] 3-2. LLM 연동 및 프롬프트 생성기 (Gemma-4 API)
- [x] 3-3. Notion 연동 클라이언트 (텍스트 업로드)
- [x] 3-4. 장애 복구 및 스케줄러 통합 (백오프 재시도 로직)

## 4. 전체 파이프라인 통합 및 검증

- [x] 4-1. 엔드투엔드 통합 테스트

## 5. 엣지 케이스 및 예외 처리 리팩토링

- [x] 5-1. Elixir: 환경변수 안전한 파싱 및 Fail-fast 로직 적용
- [x] 5-2. Elixir: 재시도(Retry) 로직 스마트화 및 통신 에러 분기
- [x] 5-3. Rust: 명시적 에러 타입(AppError) 구현 및 방어적 코드(안전한 인덱싱) 추가
- [x] 5-4. 테스트 코드 Fail-fast 검증 적용 및 Timeout 설정 최적화
