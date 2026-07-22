# 에이전트 협업 전략

- 상태: 적용

병렬 작업은 속도보다 불확실성과 변경 권한을 분리하기 위해 사용한다. 영구적인 역할이나
단계별 작업 기록을 만드는 것이 목적이 아니다. 장기 보존할 내용은 작업 경과가 아니라
각 영역 정본의 결정 근거, domain/API/schema의 현재 계약, 운영 문서의 안전 절차다.

## 원칙

1. 하나의 작업은 하나의 명확한 결과와 가능한 한 좁은 write set을 가진다.
2. 같은 계약 파일, migration, build 설정은 한 시점에 한 명만 수정한다.
3. 조사자는 기본적으로 read-only이고 코드·migration·test·실행 결과를 근거로 반환한다.
4. 구현자는 할당된 경계만 바꾸며 공용 계약 변경은 coordinator에게 넘긴다.
5. 검증자는 구현 의도보다 공개 동작, 불변식과 diff를 독립적으로 확인한다.
6. 작업별 진행·완료 보고는 thread, issue 또는 PR에 남긴다. 저장소에 Phase/task/handoff
   기록 문서를 새로 만들지 않는다.
7. 반복해서 적용할 결정은 해당 canonical 문서에 반영하고 일회성 명령 출력은
   문서 정본으로 승격하지 않는다.

## 역할과 책임

| 역할 | 책임 | 기본 권한 |
| --- | --- | --- |
| Coordinator | 범위 분해, ownership 배정, 계약 충돌과 최종 gate 통합 | 공용 문서·설정 |
| Investigator | legacy 또는 현재 구현의 증거 수집과 불일치 보고 | read-only |
| Contract owner | OpenAPI와 backend/iOS 호환 경계 결정 | `contracts/`와 관련 정본 |
| Schema owner | Flyway, JPA mapping, DB 무결성과 전환 안전성 | migration과 DB test |
| Module owner | 한 Spring Modulith module의 구현과 test | 해당 package와 test |
| iOS owner | 한 feature와 API adapter 소비 | 해당 feature와 test |
| Adapter owner | R2 또는 Firebase 같은 외부 경계 | 해당 adapter와 test |
| Verifier | 계약, 위험별 gate와 전체 diff 독립 검토 | read-only |

역할은 작업마다 정하며 영구 담당자를 뜻하지 않는다. 한 사람이 여러 역할을 맡더라도
공유 파일 ownership과 독립 검증이 필요한 고위험 변경은 분리한다.

## 작업 경계

작업 시작 전 [작업 정의 및 완료 보고](work-template.md)에 다음을 고정한다.

- 사용자가 관찰할 완료 상태와 비목표
- 수정 가능, read-only, 수정 금지 경로
- 보존할 domain/API/schema/security 계약
- 데이터·동시성·외부 provider·배포 위험
- 필수 검증과 실제 중단 조건

공유 파일의 기본 owner는 다음과 같다.

| 경로 | 단일 owner |
| --- | --- |
| `AGENTS.md`, root `README.md`, 공용 canonical 문서 | Coordinator |
| `contracts/openapi-v2.yaml` | Contract owner |
| `backend/**/db/migration/` | Schema owner |
| backend root build/wrapper와 root `Dockerfile`/`railway.json` | Backend integration owner |
| Xcode project/workspace와 package resolution | iOS integration owner |

작업 packet이 더 좁은 범위를 선언하면 그 범위가 우선한다.

## 조정 흐름

```text
실행 가능한 증거
  → 결정과 불변식 확정
  → 공개 계약과 ownership 확정
  → 독립 가능한 구현
  → 위험별 검증
  → coordinator의 계약·diff 통합
```

- 독립적인 read-only 조사는 병렬화할 수 있다.
- 서로 다른 module은 공개 계약과 의존 방향이 확정된 뒤 병렬화한다.
- OpenAPI를 소비하는 backend와 iOS는 계약 owner의 변경을 기준으로 구현한다.
- DB migration, 운영 설정, production write와 destructive action은 일반 구현과 분리한다.
- formatter, reset, rebase 또는 rollback으로 다른 작업자의 변경을 덮지 않는다.
- Local 검증과 hosted delivery 간극을 다룰 때는 repository skill
  `$manage-woorisai-delivery`와 그 delivery harness를 사용한다. Workflow와 운영 runbook이 정본이며
  harness가 어긋나면 같은 변경에서 함께 고친다.

## Branch와 승격

이 repository는 장기 `develop`/`release` branch를 두지 않는 trunk-based 흐름을 사용한다.

- `main`은 deploy 가능한 유일한 integration branch다.
- 변경은 짧은 `codex/*` 또는 feature branch에서 만들고 pull request로 `main`에 합친다.
- Repository hygiene, Backend check, Container smoke와 iOS app gates가 모두 성공해야 승격할 수
  있다. Required check로 지정할 때 path filter로 job 자체가 사라지게 만들지 않는다.
- Merge는 squash를 기본으로 하고 `main` force-push를 금지한다. Merge된 short-lived branch는
  삭제해 다시 배포 source로 사용되지 않게 한다.
- Public repository의 `main` branch protection은 pull request와 네 required check를 강제하고
  branch 삭제와 force-push를 막는다. Railway `Wait for CI`와 iOS trusted-`main` source gate는
  production artifact가 검증을 우회하지 못하게 하는 별도 실행 경계다.

Repository는 secret-scanned current tree에서 시작하는 public source다. Public ref에는 이전 private
history, credential, populated env, provider artifact와 private operator record를 push하지 않는다.
Visibility와 ref topology를 다시 바꿀 때는 전체 공개 ref의 secret scan, commit metadata 범위와
credential rotation 필요성을 별도 승인 작업으로 검토한다.

## 중단과 통합 기준

다음 상황에서는 범위를 넓혀 추측하지 않고 coordinator 또는 사용자 결정을 요청한다.

- 할당되지 않은 공유 파일이나 다른 작업자의 write set을 바꿔야 한다.
- 코드, schema, 계약 정본과 실행 결과가 서로 모순된다.
- production owner/writer 또는 destructive target이 명확하지 않다.
- 호환성 파괴, 데이터 손실, secret 접근, deploy 같은 추가 권한이 필요하다.
- PostgreSQL·device·provider 고유 결론을 해당 환경 없이 내려야 한다.

통합할 때는 변경 범위, 정본과의 일치, 실제 실행한 검증, 미검증 공백, secret·운영 영향과
전체 diff를 확인한다. 검증 기준은 [검증 매트릭스](verification-matrix.md)를 따른다.
