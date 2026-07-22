# Railway 운영

Railway는 Spring API와 PostgreSQL만 운영한다. iOS binary는 Xcode/App Store Connect release
flow가 소유하고 Railway의 public HTTPS API를 호출한다. API process 안에서 media adapter와
notification listener가 실행되며 별도 web, worker나 scheduler service는 두지 않는다.

아키텍처 근거는 [시스템 아키텍처](../architecture/system-architecture.md), credential 취급은
[보안 문서](security-and-secrets.md)를 따른다.

## Production topology

```text
Internet
  -> Railway HTTPS domain
    -> woorisai-api
      -> Railway private network -> PostgreSQL / schema woorisai
      -> Cloudflare R2
      -> Firebase FCM
```

- Public ingress는 API service만 가진다.
- PostgreSQL은 public application endpoint가 아니며 API가 private network로 연결한다.
- Business data의 유일한 runtime writer는 Spring과 `woorisai` schema다.
- R2 bucket/object는 private이고 Firebase service account는 API에만 둔다.
- API와 database의 삭제, schema drop, object bulk delete는 별도 destructive approval 없이는
  실행하지 않는다.

Staging이나 review realm을 만들 때도 같은 service shape를 사용하되 DB, bucket, Firebase
project와 credential을 production과 공유하지 않는다. Review data는 정확히 두 synthetic
participant만 사용하고 production dump를 복제하지 않는다.

## Build와 deploy 구성

Backend build가 root [OpenAPI](../../contracts/openapi-v2.yaml)를 검증하므로 Railway build
context는 repository root다. `railway.json`이 root `Dockerfile`, `/health` healthcheck와 restart
policy를 고정한다. Service root를 `backend/`로 바꾸지 않는다.

Build stage는 repository wrapper로 다음을 실행한다.

```bash
cd backend && ./gradlew --no-daemon openApiValidate bootJar
```

`.dockerignore`는 Dockerfile, Gradle build metadata, `src/main`과 canonical OpenAPI처럼 build에
필요한 파일만 전달한다. Test-only source, local output, `.env`, credential과 private artifact는
builder context에서 제외한다.

Runtime image는 non-root UID/GID로 다음 artifact만 실행한다.

```bash
java -jar /app/woorisai.jar
```

Application은 Railway가 주입한 `PORT`에 bind한다. Java image digest나 start command를 바꾸면
local image build와 fresh PostgreSQL startup smoke를 함께 수행한다.

### GitHub CI/CD

Production service는 GitHub repository root와 `main`을 source로 사용한다. Railway GitHub
autodeploy의 `Wait for CI`를 켜서 다음 순서를 보존한다.

```text
short-lived branch -> pull request -> GitHub Verify
  -> main -> GitHub Verify 성공 -> Railway Dockerfile deploy
  -> Railway /health 성공 -> GitHub production edge smoke
```

Railway가 기다리는 production gate는 Repository hygiene, Backend check, Container smoke와 iOS app
gates다. Public repository의 `main` branch protection도 같은 check를 required status로 강제하고,
Railway `Wait for CI`가 production 승격을 한 번 더 fail-closed한다.
Railway source의 root directory는 비워 repository root를 유지하고 config path는
`/railway.json`, branch는 `main`, check suite 대기는 enabled여야 한다. GitHub Actions에 Railway
token을 복제하거나 Actions와 Railway native autodeploy를 동시에 실행해 중복 배포하지 않는다.

`deployment_status=success` 뒤 실행하는 edge smoke는 GitHub repository secret
`BACKEND_BASE_URL`로 production origin을 주입하고 public `/health`, login options와 명백히 잘못된
actor의 보호 endpoint 401/no-store만 확인한다. Hostname은 credential이나 완전한 은닉 경계가
아니며, 실제 PIN, private response, R2와 FCM smoke는 일반 workflow에 넣지 않는다.
Railway가 GitHub Deployment에 쓰는 production environment 이름은 연동 버전에 따라
`production` 또는 `<project> / production`일 수 있으므로 workflow는 이 project의 두 형식만
허용한다. 최초 source 연결이나 config 변경 배포처럼 GitHub `deployment_status`가 생성되지 않은
경우에는 exact protected `main` SHA의 terminal `SUCCESS`를 먼저 확인한 뒤 `Backend production
smoke`를 `main`에서 수동 실행한다. 이 fallback은 현재 edge 검증이고, 다음 정상 `main` push에서
Railway native post-deploy event가 실제로 도착하는지는 별도로 확인한다.

## Startup과 schema

Runtime 계약은 다음과 같다.

- Flyway enabled, location `classpath:db/migration/postgresql`
- Default/schema `woorisai`, `create-schemas=true`, `baseline-on-migrate=false`
- JPA `generate-ddl=false`, `ddl-auto=validate`, `default_schema=woorisai`
- SQL init disabled

Application startup은 pending Flyway migration을 적용한 뒤 JPA mapping을 validate한다. PIN 입력,
data copy, backfill, reconcile과 destructive cleanup을 startup, build, pre-deploy hook에 넣지 않는다.
여러 replica가 함께 동작할 수 있으므로 schema와 OpenAPI 변경은 지원 중인 이전 artifact/iOS
binary와 forward compatible해야 한다.

## Runtime 변수

실제 값은 Railway variable/secret store에만 둔다.

| 범주 | 변수 | 계약 |
| --- | --- | --- |
| HTTP | `PORT` | Railway 주입 값을 사용 |
| PostgreSQL | `SPRING_DATASOURCE_URL`, `SPRING_DATASOURCE_USERNAME`, `SPRING_DATASOURCE_PASSWORD` | Private network JDBC URL과 최소 권한 owner |
| Media switch | `MEDIA_UPLOADS_ENABLED` | 기본 `false` |
| R2 | `R2_ENDPOINT_URL`, `R2_REGION_NAME`, `R2_BUCKET_NAME`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` | Media enabled일 때 전용 private bucket credential |
| Media TTL | `MEDIA_UPLOAD_URL_TTL_SECONDS`, `MEDIA_DOWNLOAD_URL_TTL_SECONDS` | 기본 900/300초, 허용 60~3600초 |
| Notification switch | `FIREBASE_NOTIFICATIONS_ENABLED` | 기본 `false` |
| Firebase | `FIREBASE_PROJECT_ID`, `FIREBASE_SERVICE_ACCOUNT_JSON_BASE64` | Notification enabled일 때 전용 service account |

### Local env 파일

Backend operator는 다음 파일을 사용할 수 있다.

- `backend/.env.local`: local PostgreSQL/provider test 입력
- `backend/.env.production`: Railway 값과 대조하거나 승인된 변경을 준비하는 local operator 입력
- `backend/.env.local.example`, `backend/.env.production.example`: commit되는 key schema와 안전한
  기본값

실제 두 파일은 Git과 Docker context에서 제외하고 mode `0600`으로 유지한다. `.env.production`은
Railway나 password manager의 대체 정본이 아니며 `git clean -xdf`, 장비 손실이나 stale copy로
사라지거나 오래될 수 있다. Production runtime의 정본은 Railway variable/secret store다.

다음 검사는 값을 출력하지 않고 key set, 형식, provider switch의 조건부 필수값만 확인한다.

```bash
backend/scripts/validate-env.sh local
backend/scripts/validate-env.sh production
```

파일을 shell에서 `source`하거나 `set -x`, `env`, `printenv`로 출력하지 않는다. Railway variable을
바꿀 때는 exact project/environment/service를 확인하고 한 값을 stdin으로 전달하며, 변경이 만드는
redeploy와 provider 중복 의미를 먼저 승인한다.

PostgreSQL reference variable을 쓰더라도 최종 datasource URL은 Spring이 읽는
`jdbc:postgresql://...` 형식이어야 한다. Service 간 reference를 만들 때 consumer가 실제로
필요한 값만 참조하고, service 삭제 전 모든 dependent reference를 먼저 제거한다.

Media switch가 false면 storage-dependent endpoint는 unavailable이고 DB-backed attachment
mapping은 계속 validate된다. Firebase switch가 false이거나 provider가 실패하면 listener는
publication을 outstanding으로 남긴다. Provider 활성화나 restart는 재전송과 중복을 만들 수
있으므로 staging에서 의미를 확인한 뒤 production에 적용한다.

## Health

`GET /health`는 public Actuator readiness path다.

- Readiness group은 `readinessState`와 production DataSource `db`를 포함한다.
- DB가 down 또는 out-of-service면 503을 반환한다.
- Component detail, SQL과 provider configuration은 public response에 노출하지 않는다.
- R2/Firebase 상태는 DB readiness에 포함하지 않는다. 두 provider는 핵심 DB write와 다른 실패
  경계를 갖기 때문이다.
- 다른 Actuator endpoint는 public expose하지 않는다.

Staging에서는 정상 200뿐 아니라 DB 연결 차단 시 503과 복구를 smoke한다. Fresh container
startup과 unit/PostgreSQL test만으로 Railway edge, private network와 restart recovery가
검증됐다고 간주하지 않는다.

## Deploy gate

배포할 source revision 하나를 고정하고 다음을 확인한다.

```bash
cd backend
./gradlew --no-daemon check bootJar
cd ..
docker build --pull --tag woorisai:local .
```

- OpenAPI validation과 지원 중인 iOS client compatibility
- Fresh PostgreSQL startup, Flyway/JPA validate와 `/health` 200/503
- Media enabled/disabled startup과 분리된 staging R2 E2E
- Firebase enabled/disabled startup, test-device delivery와 restart republish
- Authorization, PIN, FID와 presigned URL redaction
- Environment별 DB/R2/Firebase 격리
- Current production backup과 rollback decision owner

`main` push의 GitHub check가 실패하거나 누락되면 Railway deployment는 시작하지 않는다. Config
변경이나 수동 deploy도 같은 source revision과 gate 결과를 연결하고, queued/building 상태를 성공으로
보고하지 않는다. Railway deployment가 terminal `SUCCESS`이고 edge smoke가 성공해야 배포 완료다.

Health가 성공한 뒤 public login options, invalid credential 401과 승인된 synthetic/real credential
smoke를 구분해 기록한다. 실제 PIN이나 private response content는 배포 log에 남기지 않는다.

## Backup과 recovery

- Production backup은 `woorisai` schema뿐 아니라 복구에 필요한 database 범위를 암호화해
  보관한다.
- Backup은 checksum, 접근 권한, retention과 복구 owner를 갖는다.
- Restore 가능성은 production과 분리한 PostgreSQL에서 schema, constraints와 representative
  aggregate를 확인해 검증한다.
- R2 object와 DB metadata는 서로 다른 저장소이므로 DB restore가 object byte까지 복구한다고
  가정하지 않는다.
- Provider credential과 signing key는 DB backup에 포함하지 않는다.

## 장애와 rollback

Application failure에서는 먼저 maintenance를 유지하고 DB/schema가 바뀌었는지 확인한다.

1. Schema와 OpenAPI가 이전 artifact와 forward compatible하면 이전 Railway deployment를
   활성화할 수 있다.
2. 호환되지 않으면 migration을 내리지 말고 forward fix를 우선한다.
3. Data corruption이면 write를 중지하고 current encrypted backup restore 또는 승인된
   reconciliation을 선택한다.
4. Provider 장애는 핵심 DB write를 되돌리는 이유가 아니다. Media/notification switch와
   outstanding work의 의미를 각각 확인한다.

Flyway migration rollback, `woorisai` schema drop, backup restore와 R2 object 삭제는 자동화된
rollback step이 아니다. 대상, backup, expected loss와 승인자를 확인한 별도 작업으로 실행한다.

## 참고

- [Railway config-as-code](https://docs.railway.com/config-as-code/reference)
- [Railway Dockerfile build](https://docs.railway.com/builds/dockerfiles)
- [Railway GitHub deployments](https://docs.railway.com/deployments/github-autodeploys)
- [Railway monorepo deployment](https://docs.railway.com/deployments/monorepo)
