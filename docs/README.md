# 문서 지도

이 디렉터리에는 현재 시스템을 설명하는 근거와 계약만 둔다. Git 이력, CI, App Store Connect,
Railway와 private operator record가 실행 이력을 보존하므로 phase별 handoff나 배포 일지를
canonical 문서로 복제하지 않는다.

## 문서 유형

- **Architecture/domain reference**: 현재 구조·불변식과 이를 소유하는 선택의 이유,
  trade-off와 재검토 조건
- **Runbook**: 지금 반복 실행할 수 있는 운영·release 절차와 중단 조건
- **Contract**: backend와 client가 함께 따르는 공개 wire schema

날짜별 상태, commit/deployment ID, row count, 일회성 migration 명령과 당시 테스트 결과는 위
유형에 포함하지 않는다. 그런 증거가 필요하면 Git/CI 또는 승인된 외부 운영 기록을 조회한다.

## Architecture

- [시스템 아키텍처](architecture/system-architecture.md)
- [Spring Modulith module 경계](architecture/module-boundaries.md)
- [SwiftUI iOS 아키텍처](architecture/ios-architecture.md)

## Domain

- [도메인·운영 불변식](domain/invariants.md)
- [Clean data model](domain/data-model.md)
- [미디어 lifecycle](domain/media-lifecycle.md)
- [Notification 계약](domain/notification-contract.md)

## Operations

- [Railway](operations/railway.md)
- [iOS release](operations/ios-release.md)
- [보안과 비밀](operations/security-and-secrets.md)

## API contract

- [계약 안내](../contracts/README.md)
- [OpenAPI 3.1](../contracts/openapi-v2.yaml)

## Agent workflow

- [협업 원칙](agent/strategy.md)
- [작업 템플릿](agent/work-template.md)
- [검증 매트릭스](agent/verification-matrix.md)

## 정본 우선순위

1. 공개 wire는 OpenAPI가 정본이다.
2. Database shape는 적용된 Flyway와 JPA mapping이 정본이다.
3. Business 의미는 domain invariant와 owning module test가 정본이다.
4. 선택 이유와 승인한 trade-off는 해당 architecture, domain 또는 contract 문서가 소유한다.
5. 운영 절차는 현재 runbook이 정본이다.

문서와 실행 가능한 계약이 다르면 code, migration, schema와 test를 먼저 확인한 뒤 같은 변경에서
문서를 갱신한다. 실행 결과를 문서에 덧붙이는 대신 결정이나 반복 절차가 실제로 바뀌었을 때만
canonical 문서를 수정한다. 기존 소유 문서가 없는 새 주제만 별도 문서로 만들고 이 지도에
연결한다. 별도 결정 기록 디렉터리는 두지 않는다.
