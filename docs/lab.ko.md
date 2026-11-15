# Cloud Ticketing 실습

행사 신청 사이트 하나를 자신의 Google Cloud 프로젝트에 직접 만들고 운영합니다. 앱 코드는 완성되어 있고, 이번 실습에서 코드는 짜지 않습니다. 클라우드 쪽은 콘솔에서 직접 만들고, 반복 작업은 `./lab` 단축 명령이 대신합니다. 만든 뒤에는 관찰하고, 일부러 고장 내고, 고치고, 측정합니다.

| | |
|---|---|
| 수준 | 입문 (200) |
| 시간 | 2시간 세션(D0) + 1주 동안 7~9시간 |
| 비용 | 무료 체험 크레딧에서 차감. 예산 12,000원 설정, 실제 비용은 26단계에서 확인 |
| 마지막 점검 | 아직 없음 (전체 시험 후 날짜 기록) |

**마치면 할 수 있는 것**

- 신청이 몰리는 서비스에 필요한 클라우드 부품을 문제 순서대로 설명
- Cloud Run 서비스, Pub/Sub, Eventarc, Cloud Scheduler, Firestore를 콘솔에서 만들고 연결
- 실패(시작 실패, 403, 404, 재시도, dead letter)를 로그에서 찾아 원인이 된 설정 하나로 연결
- GitHub Actions에서 키 없이 배포하고, 깨진 버전이 사용자에게 닿지 않는 이유 설명
- 콜드 스타트, 자동 확장, 동시성, 사전 준비를 자신의 측정값으로 비교

## 읽는 법

- ☰는 콘솔 왼쪽 위의 탐색 메뉴입니다. "☰ → **Pub/Sub → 구독**"은 ☰에서 **Pub/Sub**를 누르고 왼쪽 메뉴의 **구독**을 누르라는 뜻입니다. 메뉴에 없으면 맨 아래 전체 제품 목록에서 찾습니다.
- 굵은 글씨는 콘솔의 버튼과 칸 이름입니다. 콘솔이 영어로 보이면 괄호 안의 영어 이름을 찾습니다.
- 모든 화면에서 위쪽 프로젝트 메뉴에 실습 프로젝트가 선택되어 있는지 먼저 봅니다.
- 콘솔에서 **작업**(Jobs)이라고 표시되는 것이 이 문서의 **잡**입니다.
- `프로젝트_ID`, `프로젝트_번호`처럼 밑줄 이름은 자신의 값으로 바꿉니다. 둘 다 ☰ → **IAM 및 관리자 → 설정**에 있습니다.

**단계의 종류**

| 표시 | 뜻 |
|---|---|
| 직접 | 콘솔에서 직접 만듭니다. 끝나면 `./lab check 단계`로 확인합니다 |
| 단축 | `./lab` 명령이 만듭니다. 바로 아래 **콘솔로 직접 하기**에 같은 일을 손으로 하는 방법이 있습니다. 명령은 없는 것만 만들기 때문에, 손으로 일부를 만든 뒤 실행해도 됩니다 |
| 실험 | 예측하고, 해 보고, 확인하고, 이유를 씁니다 |

**각 단계의 구성:** 문제 → 할 일 → 예측 → 어디서 볼까 → 확인 → 이유, 막히면.

**막혔을 때:** 20분 넘게 막히면 도움 스레드에 단계 번호, `./lab check 단계` 출력, 오류 화면을 올립니다. 기다리지 않고 넘어가려면 `./lab skip 단계`로 그 단계를 만들고 다음으로 갑니다. 건너뛴 단계는 보고서에 표시됩니다.

## 어디서 볼까

| 개념 (행사의 순간) | 단계 | 볼 곳 | 보여야 하는 것 |
|---|---|---|---|
| 자동 확장 (오픈 순간) | 23, 24 | ☰ → **Cloud Run** → `web` → **모니터링 가능성**(Observability) → **측정항목**: 컨테이너 인스턴스 수, 요청 지연 시간 | 신청이 몰리면 인스턴스가 늘고, 끝나면 줄어듦 |
| 0까지 축소 (밤) | 22, 26 | 같은 그래프의 긴 대기 후 구간, ☰ → **결제 → 보고서** | 인스턴스 0, 쓴 시간만큼만 비용 |
| 서버 밖의 상태 (행사 등록) | 2, 16 | ☰ → **Firestore** → **Firestore Studio**: `events`, `registrations` | 새 리비전 뒤에도 데이터 그대로 |
| 트랜잭션 (마지막 한 자리) | 23 | Firestore Studio → `event_counts` → 자신의 행사 | `held`와 `issued`가 정원과 같음 |
| 대기열 (신청 직후) | 7, 8 | ☰ → **Pub/Sub → 구독** → `ticket-worker` → **메시지**, **측정항목** | 가져오기일 때 메시지 대기, 푸시 후 0 |
| 재시도, 멱등성, dead letter (발급 실패) | 9, 10 | `ticket-worker`의 **로그**, `dead-letter` 구독의 **메시지** | 간격이 늘어나는 500, dead letter로 옮겨진 메시지, 중복은 `skip` |
| 이벤트 기반 (취소) | 11 | ☰ → **Eventarc → 트리거**, `waitlist-promoter`의 **로그** | 취소 몇 초 뒤 대기자 배정 로그 |
| 예약 작업 (확인 마감) | 12 | ☰ → **Cloud Run → 작업** → `housekeeping` → **기록**, ☰ → **Cloud Scheduler** | 5분마다 실행, 반환된 좌석 |
| 콜드 스타트, 사전 준비 (오픈 15분 전) | 22, 25 | `web`의 인스턴스 수 그래프, **YAML** 탭의 `minScale` | 느린 첫 요청, 오픈 전에 준비된 인스턴스 3개 |
| 누가 무엇을 할 수 있나 | 3, 5, 8, 20 | ☰ → **IAM 및 관리자 → IAM**, `./lab iam`, 각 서비스의 **보안** 탭과 **네트워킹** 탭, 보안 비밀의 **권한** 탭 | 시작 실패, 403, 404마다 원인이 된 설정 하나 |
| 안전한 변경 | 15~19 | GitHub **Actions**, `web`의 **수정 버전**(Revisions) 탭 | 0% 리비전, 검사, 전환. 실패한 리비전은 트래픽 0 |
| 관찰 | 21, 23 | ☰ → **Logging → 로그 탐색기** | 같은 티켓 코드가 `web`과 `ticket-worker` 로그에 |
| 데이터 보관 기한 (30일 후) | 3 | ☰ → **Firestore** → **TTL** | 정책 5개, 사용 중 |

## 일정

| 날 | 단계 | 시간 |
|---|---|---|
| D0 세션 | 0~3: 프로젝트, `./lab start`, Firestore, `./lab base` | 세션 중 70분 |
| D1 | 4~7: 주제와 구독, `web` 배포, 워커, 첫 신청 | 75분 |
| D2 | 8~10: 푸시 연결, 멱등성, 재시도와 dead letter | 75분 |
| D3 | 11~13: Eventarc, 잡과 Scheduler, 사전 준비 권한 | 60분 |
| D4 | 14~19: GitHub 복사본, 키 없는 로그인, 배포, 실패와 롤백 | 100분 |
| D5 | 20~25: 접근 제어, 로그, 콜드 스타트, 부하 테스트 | 110분 |
| D6~7 | 26~27: 비용, 일시중지, 제출과 확인 면담 | 45분 |

![아키텍처](architecture.png)

---

# D0. 세션

## 0단계. 프로젝트와 예산 (직접, 10분)

**문제.** 실습 비용을 모르고 시작하면, 켜 둔 것이 있는지 끝까지 모릅니다.

**할 일.**
1. ☰ → **IAM 및 관리자 → 리소스 관리** → **프로젝트 만들기**. 이름 아래의 **프로젝트 ID**를 적어 둡니다.
2. ☰ → **결제 → 내 프로젝트**에서 새 프로젝트에 결제 계정이 연결되어 있는지 봅니다. 없으면 행의 **작업** 메뉴 → **결제 변경**.
3. ☰ → **결제 → 예산 및 알림** → **예산 만들기**. 범위: 실습 프로젝트. 금액: 12,000원. 알림은 기본값.

**확인.** 1단계를 마친 뒤 `./lab check 0`.

**이유.** 예산은 알림만 보냅니다. 서비스를 멈추지는 않습니다. **"전체 계정으로 업그레이드"는 누르지 않습니다.**

## 1단계. Cloud Shell과 `./lab start` (단축, 15분)

**문제.** 새 프로젝트는 거의 모든 서비스가 꺼져 있고, 배포할 이미지도 없습니다.

**할 일.**
1. 콘솔 오른쪽 위의 **Cloud Shell 활성화**(>_ 아이콘)를 누릅니다.
2. GitHub에 로그인합니다. Enter를 누르고 화면의 코드를 [github.com/login/device](https://github.com/login/device)에 입력합니다.

   ```bash
   gh auth login --web --scopes workflow
   ```

3. 실습 저장소를 받고 시작합니다.

   ```bash
   gh repo clone joyrla/gdgoc-tickets-lab
   cd gdgoc-tickets-lab
   ./lab start 프로젝트_ID
   ```

`./lab start`가 하는 일: 도구 설치, API 켜기, 이미지 저장소(Artifact Registry) `gdgoc-tickets` 만들기, 이미지 4개를 백그라운드에서 빌드하기(5분쯤). 빌드가 도는 동안 2단계로 넘어갑니다.

<details>
<summary>콘솔로 직접 하기</summary>

1. ☰ → **API 및 서비스 → 라이브러리**에서 하나씩 검색해 **사용**을 누릅니다: Cloud Run Admin API, Artifact Registry API, Cloud Firestore API, Cloud Pub/Sub API, Secret Manager API, Eventarc API, Cloud Scheduler API, IAM Service Account Credentials API, Security Token Service API, Cloud Billing Budget API.
2. ☰ → **Artifact Registry → 저장소** → **저장소 만들기**. 이름 `gdgoc-tickets`, 형식 **Docker**, 모드 **표준**, 위치 유형 **리전**, `asia-northeast3 (서울)`. **만들기**. 모드가 **표준**인지 만들기 전에 다시 봅니다.
3. 그다음 `./lab start 프로젝트_ID`를 실행합니다. 이미 있는 것은 그대로 두고, 설정 기록과 이미지 빌드만 합니다. 이미지는 명령으로만 만듭니다(`./lab images`).
</details>

**확인.** 마지막 줄이 `Done.`입니다. 5분 뒤 `./lab check 1`에서 이미지 4개가 `ok`.

**막히면.**

| 메시지 | 해결 |
|---|---|
| `cannot see project` | 프로젝트 ID 오타. 프로젝트 이름과 다릅니다 |
| `no billing account linked` | 0단계의 2번 |
| `image ... is missing` | 아직 빌드 중. `tail ~/.gdgoc-lab/images.log`, 멈췄으면 `./lab images` |

Cloud Shell은 오래 쉬면 끊깁니다. 다시 열면 `cd ~/gdgoc-tickets-lab`부터 합니다.

## 2단계. Firestore 데이터베이스 (직접, 10분)

**문제.** Cloud Run은 요청이 많으면 서버 복사본(인스턴스)을 늘리고, 없으면 지웁니다. 복사본마다 메모리가 따로이고 언제든 사라지므로, 좌석 수와 신청은 서버 밖에 있어야 합니다.

**할 일.** ☰ → **Firestore** → **데이터베이스 만들기**.

| 칸 | 값 |
|---|---|
| 데이터베이스 ID | `(default)` |
| 버전(Edition) | **Standard** |
| 보안 규칙 | **제한적**(Restrictive) |
| 위치 유형 | **리전**, `asia-northeast3 (서울)` |
| 재해 복구(PITR, 삭제 보호) | 끔 |

**리전과 버전은 만든 뒤 바꿀 수 없습니다.** 잘못 만들면 지우고 새로 만들어야 합니다. **데이터베이스 만들기**.

**예측.** 보안 규칙을 "제한적"으로 두면 서비스가 데이터를 못 읽을까요?

**어디서 볼까.** ☰ → **Firestore** → `(default)` → **Firestore Studio**. 아직 비어 있습니다.

**확인.** `./lab check 2`

**이유.** 보안 규칙은 브라우저와 앱의 Firebase SDK에만 적용됩니다. 서비스는 서버 라이브러리와 IAM 권한으로 접근하므로 규칙의 영향을 받지 않습니다. Standard 버전의 트랜잭션은 읽은 문서를 잠가서, 마지막 한 자리를 두 사람에게 주지 않습니다.

**막히면.** 다른 리전으로 만들었다면 ☰ → **Firestore** → 데이터베이스 → **삭제** 후 다시 만듭니다. 또는 `./lab skip 2`.

## 3단계. `./lab base`와 `./lab iam` (단축, 설명, 15분)

**문제.** 서비스마다 신분(서비스 계정), 서명 키(보안 비밀), 파일 저장소, 개인정보 삭제 기한이 필요합니다. 클릭은 많고 배울 것은 적은 부분입니다.

**할 일.**

```bash
./lab base
./lab iam
```

`./lab base`가 만드는 것: 컬렉션 5개의 TTL(만료) 규칙, 대기자 조회용 색인, 비공개 버킷 `프로젝트_ID-assets`, 서비스 계정 8개, 보안 비밀 4개, 런타임 계정 4개의 Firestore 권한, 버킷 권한.

<details>
<summary>콘솔로 직접 하기</summary>

**TTL.** ☰ → **Firestore** → `(default)` → **TTL** → **정책 만들기**. 컬렉션 그룹 `registrations`, `codes`, `emails`, `login_codes`, `sent_emails` 각각, 타임스탬프 필드 `expire_at`.

**만료 필드 색인 제외.** ☰ → **Firestore** → `(default)` → **색인** → **자동**(Automatic) 탭 → **예외 추가**. 위 컬렉션 5개 각각, 필드 경로 `expire_at`, 쿼리 범위 **컬렉션**, 오름차순, 내림차순, 배열을 모두 **사용 중지**.

**대기자 색인.** **색인** → **수동**(Manual) 탭 → **색인 만들기**. 컬렉션 ID `registrations`, 필드 `event_id` 오름차순, `status` 오름차순, `created_at` 오름차순, 쿼리 범위 **컬렉션**.

**버킷.** ☰ → **Cloud Storage → 버킷** → **만들기**. 이름 `프로젝트_ID-assets`, 리전 `asia-northeast3`, 공개 액세스 방지 **사용**, 액세스 제어 **균일**. 만든 뒤 **수명 주기** 탭 → **규칙 추가**: 객체 삭제, 이름 프리픽스 `tickets/`, 기간 90일.

**서비스 계정.** ☰ → **IAM 및 관리자 → 서비스 계정** → **서비스 계정 만들기**, 8번. ID와 역할:

| ID | 프로젝트 역할 |
|---|---|
| `tickets-web` | Cloud Datastore 사용자 |
| `tickets-ticket-worker` | Cloud Datastore 사용자 |
| `tickets-waitlist-promoter` | Cloud Datastore 사용자 |
| `tickets-housekeeping` | Cloud Datastore 사용자 |
| `tickets-pubsub-push` | 없음 |
| `tickets-eventarc` | 없음 |
| `tickets-scheduler` | 없음 |
| `tickets-deployer` | 없음 |

**보안 비밀.** ☰ → **보안 → 보안 비밀 관리자** → **보안 비밀 만들기**. `ticket-secret`, `session-secret`은 값으로 임의의 32자(영문, 숫자)를 넣습니다. `smtp-password`, `mail-from`은 값 없이 만듭니다(메일은 꺼져 있음). 읽기 권한은 여기서 주지 않습니다. 5단계와 6단계에서 줍니다.

**버킷 권한.** 버킷 → **권한** → **액세스 권한 부여**. `tickets-web`, `tickets-ticket-worker`에 **스토리지 객체 사용자**.

다 만들었다면 `./lab base`를 실행해도 아무것도 새로 만들지 않습니다.
</details>

**예측.** 서비스 계정을 서비스마다 하나씩 두는 이유는 무엇일까요?

**어디서 볼까.** `./lab iam`의 표. 같은 내용이 ☰ → **IAM 및 관리자 → IAM**과 각 자원의 **권한** 탭에 흩어져 있습니다.

**확인.** `./lab check 3`. `./lab iam`에서 계정 하나를 골라, 권한마다 "무엇을 위해 필요한가"를 말할 수 있으면 됩니다(퀴즈 7번).

**이유.** 서비스 하나가 침해되어도 그 서비스의 권한만큼만 피해가 납니다. `web`은 메일 비밀번호를 읽지 못하고, 워커는 `web`을 바꾸지 못합니다. 권한은 가능하면 자원 하나(버킷 하나, 보안 비밀 하나)에 줍니다.

**막히면.** `./lab check 3`의 `NOT` 줄이 무엇이 빠졌는지 말해 줍니다. `./lab base`를 다시 실행해도 됩니다.

---

# D1. 신청이 들어오는 길

## 4단계. 주제와 구독 (직접, 20분)

**문제.** 신청 직후 할 일(QR 만들기, 메일 보내기)은 느리고 실패할 수 있습니다. 신청 응답이 그 일을 기다리면, 몰리는 순간 모두가 기다립니다. 그래서 `web`은 "신청됨" 메시지만 남기고 바로 응답합니다.

**할 일.**
1. ☰ → **Pub/Sub → 주제** → **주제 만들기**, 3번: `registrations`, `emails`, `dead-letter`. 매번 **기본 구독 추가**의 체크를 해제합니다.
2. ☰ → **Pub/Sub → 구독** → **구독 만들기**: dead letter를 담아 둘 구독.

   | 칸 | 값 |
   |---|---|
   | 구독 ID | `dead-letter` |
   | 주제 | `projects/프로젝트_ID/topics/dead-letter` |
   | 전송 유형 | **가져오기**(Pull) |
   | 확인 기한 | 600초 |
   | 만료 기간 | **만료되지 않음** |

3. **구독 만들기**를 한 번 더: 티켓을 만들 구독. **지금은 가져오기**로 만듭니다.

   | 칸 | 값 |
   |---|---|
   | 구독 ID | `ticket-worker` |
   | 주제 | `projects/프로젝트_ID/topics/registrations` |
   | 전송 유형 | **가져오기** |
   | 확인 기한 | 60초 |
   | 만료 기간 | **만료되지 않음** |
   | 재시도 정책 | **지수 백오프 지연 후 재시도**, 최소 10초, 최대 300초 |
   | 데드 레터링 | 사용, 주제 `dead-letter`, 최대 전송 시도 **5** |

4. 만든 뒤 열리는 **데드 레터 처리**(Dead lettering) 탭에서 **게시자 역할 부여**와 **구독자 역할 부여**를 누릅니다.

**예측.** 구독이 아직 아무 데도 메시지를 보내지 않으면, 그동안 들어온 메시지는 사라질까요?

**어디서 볼까.** 구독 `ticket-worker` → **세부정보**와 **데드 레터 처리** 탭.

**확인.** `./lab check 4`

**이유.** 주제는 메시지를 받는 이름이고, 구독은 그 메시지를 한 수신자에게 전달합니다. 구독은 메시지를 보관 기간(기본 7일) 동안 갖고 있다가 수신자가 가져가거나 받아야 지웁니다. 5번 실패한 메시지는 `dead-letter`로 옮겨져 사람이 봅니다. 4번의 두 역할은 Pub/Sub 자신이 실패한 메시지를 옮기는 데 필요합니다.

**막히면.** 기본 구독을 지우지 못하고 만들었으면 그 구독(`registrations-sub` 등)을 삭제합니다. 데드 레터 탭의 경고가 남아 있으면 버튼을 다시 누릅니다. 또는 `./lab skip 4`.

## 5단계. `web` 배포 (직접, 일부러 실패, 25분)

**문제.** 신청을 받을 공개 서비스가 필요합니다. 이 서비스는 티켓과 로그인 쿠키에 서명하므로 서명 키를 읽어야 합니다.

**할 일.**
1. Cloud Shell에서 붙여 넣을 값을 출력합니다.

   ```bash
   ./lab env web
   ```

2. ☰ → **Cloud Run → 서비스** → **컨테이너 배포**(Deploy container) → **서비스**.

   | 칸 | 값 |
   |---|---|
   | 컨테이너 이미지 URL | `./lab env web`의 `image:` 줄 |
   | 서비스 이름 | `web` |
   | 리전 | `asia-northeast3 (서울)` |
   | 인증 | **공개 액세스 허용**(Allow public access) |
   | 결제 | **요청 기반** |
   | 서비스 확장 | 자동 확장, 최소 0, 최대 20 |
   | 인그레스 | **모두** |

3. **컨테이너, 네트워킹, 보안**을 펼칩니다.

   | 위치 | 값 |
   |---|---|
   | 컨테이너 → **설정** | 메모리 512MiB, CPU 1, **시작 CPU 부스트** 켬 |
   | 컨테이너 → **설정 → 상태 확인 추가** | **시작 프로브**(Startup check), HTTP, 경로 `/health`, 포트 8080, 기간 2초, 실패 임계값 30 |
   | 컨테이너 → **요청** | 요청 제한 시간 300초, 인스턴스당 최대 동시 요청 수 40 |
   | 컨테이너 → **변수 및 보안 비밀** → **변수 추가** | 첫 **이름** 칸에 `./lab env web`의 변수 블록 전체를 붙여 넣기 |
   | 컨테이너 → **변수 및 보안 비밀** → **보안 비밀 참조** | `TICKET_SECRET` → `ticket-secret` 버전 1, `SESSION_SECRET` → `session-secret` 버전 1 |
   | **보안** 탭 | 서비스 계정 `tickets-web` |

4. 보안 비밀 옆에 권한 경고나 **부여**(Grant) 버튼이 보여도 **누르지 않습니다.**
5. **만들기**.

이 양식에서는 Enter가 바로 제출됩니다. 칸은 클릭으로 옮깁니다.

**예측.** `web`이 시작될까요?

**어디서 볼까.** `web` 서비스 화면의 오류 메시지, **수정 버전**(Revisions) 탭의 빨간 표시.

**확인.** 시작에 실패합니다. 메시지에 `Permission denied on secret`와 `tickets-web`이 보입니다.

이제 고칩니다.
1. ☰ → **보안 → 보안 비밀 관리자** → `ticket-secret` → **권한** 탭 → **액세스 권한 부여**.
2. 새 주 구성원 `tickets-web@프로젝트_ID.iam.gserviceaccount.com`, 역할 **Secret Manager 보안 비밀 접근자**. **저장**.
3. `session-secret`에도 같은 권한을 줍니다.
4. ☰ → **Cloud Run** → `web` → **수정 및 새 버전 배포**(Edit & deploy new revision) → **배포**.

이번에는 초록색 체크가 나오고, 서비스 URL을 열면 첫 화면이 보입니다. `./lab check 5`.

**이유.** 서비스는 자기 서비스 계정으로 실행되고, 그 계정에 없는 권한은 쓸 수 없습니다. 권한은 프로젝트 전체가 아니라 보안 비밀 하나에 줬습니다. 그래서 `web`은 메일 비밀번호(`smtp-password`)를 읽지 못합니다.

> **S1:** 실패한 리비전의 메시지, 그다음 정상 실행 화면

**막히면.** `runs as ... not tickets-web`: **보안** 탭의 서비스 계정. 변수가 한 줄로 합쳐졌으면 **변수 및 보안 비밀**에서 하나씩 고칩니다. 또는 `./lab skip 5`.

## 6단계. `./lab workers` (단축, 비교, 10분)

**문제.** 티켓을 만드는 `ticket-worker`, 빈자리를 대기자에게 주는 `waitlist-promoter`가 필요합니다. 둘 다 인터넷에서 부를 일이 없습니다.

**할 일.**

```bash
./lab workers
```

만드는 것: 워커 두 개, `mailer` 구독(로그인 코드 메일이 지나가는 길), 주제와 보안 비밀 권한, `tickets-pubsub-push`가 `ticket-worker`를 부를 권한, `tickets-eventarc`의 이벤트 수신 권한.

<details>
<summary>콘솔로 직접 하기</summary>

**서비스 두 개.** 5단계와 같은 양식으로 만들되, 다른 값만 적습니다. 변수는 `./lab env web`의 블록에서 `DEAD_LETTER_SUBSCRIPTION`, `SIGNUPS_PER_MINUTE_PER_IP` 두 줄을 뺀 것입니다.

| 칸 | `ticket-worker` | `waitlist-promoter` |
|---|---|---|
| 이미지 | `.../ticket-worker:lab` | `.../waitlist-promoter:lab` |
| 인증 | **인증 필요** | **인증 필요** |
| 인그레스 | **내부** | **내부** |
| 최대 인스턴스 | 5 | 3 |
| 요청 제한 시간 | 60초 | 60초 |
| 인스턴스당 최대 동시 요청 수 | 2 | 2 |
| 보안 비밀 | `TICKET_SECRET` → `ticket-secret` 1 | 없음 |
| 서비스 계정 | `tickets-ticket-worker` | `tickets-waitlist-promoter` |

**`mailer` 구독.** ☰ → **Pub/Sub → 구독** → **구독 만들기**. ID `mailer`, 주제 `emails`, **푸시**, 엔드포인트 `https://ticket-worker-프로젝트_번호.asia-northeast3.run.app/mail`, **인증 사용 설정**, 서비스 계정 `tickets-pubsub-push`, 대상(Audience) `https://ticket-worker-프로젝트_번호.asia-northeast3.run.app`, 확인 기한 60초, 만료되지 않음, 지수 백오프 10~300초, 데드 레터 `dead-letter` 50회. 만든 뒤 **데드 레터 처리** 탭에서 **구독자 역할 부여**.

**권한.**

| 자원 | 주 구성원 | 역할 |
|---|---|---|
| 서비스 `ticket-worker` (Cloud Run → 서비스에서 체크 → **권한**) | `tickets-pubsub-push` | Cloud Run 호출자 |
| 보안 비밀 `ticket-secret`, `smtp-password`, `mail-from` | `tickets-ticket-worker` | Secret Manager 보안 비밀 접근자 |
| 주제 `registrations` (주제 체크 → **권한**) | `tickets-web`, `tickets-waitlist-promoter`, `tickets-housekeeping` | Pub/Sub 게시자 |
| 주제 `emails` | `tickets-web`, `tickets-ticket-worker`, `tickets-housekeeping` | Pub/Sub 게시자 |
| 구독 `dead-letter` | `tickets-web` | Pub/Sub 구독자 |
| 프로젝트 (☰ → **IAM 및 관리자 → IAM** → **액세스 권한 부여**) | `tickets-eventarc` | Eventarc 이벤트 수신자 |
</details>

**예측.** 두 워커의 인그레스와 동시 요청 수는 `web`과 어떻게 다를까요? 왜일까요?

**어디서 볼까.** ☰ → **Cloud Run** → 각 서비스의 **네트워킹** 탭(인그레스)과 **확장** 탭과 **컨테이너** 탭(동시성, 최대 인스턴스).

**확인.** `./lab check 6`. `web`은 인그레스 **모두**, 동시성 40. 워커는 **내부**, 동시성 2.

**이유.** 워커는 Google Cloud 안(Pub/Sub, Eventarc)에서만 부르므로 인터넷 쪽 문을 닫습니다. 동시성 2 × 최대 5개 = 한 번에 티켓 10장까지. 메일 서비스와 Firestore에 한꺼번에 몰리지 않게 속도를 제한하는 것입니다.

**막히면.** `Step 4 first`: 주제 3개가 있어야 합니다. `images are not in the registry yet`: 1단계의 빌드가 끝나기를 기다립니다.

## 7단계. 첫 신청 (실험, 20분)

**문제.** 신청 응답은 왔는데 티켓이 아직 없다면, 그 사이의 일은 어디에 있을까요?

**할 일.**
1. `web`의 URL 끝에 `/login`을 붙여 엽니다. 이메일은 Cloud Shell에 로그인한 Google 계정입니다. **코드 받기**.
2. ☰ → **Logging → 로그 탐색기**. 쿼리에 `"sign-in code for organizer"`를 넣고 **쿼리 실행**. 맨 위 줄 끝의 6자리를 입력합니다. 처음에는 20초쯤 걸립니다. (`./lab code`도 같은 줄을 보여 줍니다.)
3. `/admin` → **새 행사 만들기**. 시각은 모두 한국 시간입니다.

   | 항목 | 값 |
   |---|---|
   | 행사 이름, 장소 | 자유 |
   | 주소 | `wiring` |
   | 신청 시작 | 2시간 전 |
   | 신청 마감 | 내일 |
   | 시작, 종료 | 모레 |
   | 참석 확인 마감 | 내일과 모레 사이 |
   | 정원, 대기 정원 | 200, 50 |
   | 공개 | 체크 |

   이후 행사는 달라지는 값만 적습니다. **공개를 체크하지 않으면 신청 페이지가 열리지 않습니다.**

4. `/events/wiring`에서 신청합니다.

**예측.** 티켓 화면에 무엇이 보일까요?

**어디서 볼까.** ☰ → **Pub/Sub → 구독** → `ticket-worker` → **메시지** 탭 → **가져오기**. **메시지 확인(ack)** 체크는 해제한 채로 가져옵니다.

**확인.** 티켓은 **티켓 발급 중**에 머뭅니다. 구독에 `{"registration_id": ...}` 메시지 하나가 기다리고 있습니다.

**이유.** `web`은 좌석을 Firestore에 저장하고 메시지를 남긴 뒤 바로 응답했습니다. 가져오기 구독은 누가 가져갈 때까지 메시지를 갖고만 있습니다. 메시지는 사라지지 않습니다.

> **S2:** 기다리는 메시지와 "발급 중" 티켓 화면

**막히면.** 코드가 안 보이면 30초 뒤 다시 쿼리합니다. `mail_off` 오류: `/login`에 넣은 이메일이 `ADMIN_EMAILS`와 다릅니다(`./lab env web`).

---

# D2. 백그라운드 작업과 실패

## 8단계. 가져오기 → 푸시 (직접, 일부러 실패, 20분)

**문제.** 메시지가 기다리기만 하면 티켓은 영원히 나오지 않습니다. 구독이 메시지를 `ticket-worker`로 보내야 합니다.

**할 일.**
1. ☰ → **Cloud Run** → `ticket-worker`의 **URL**을 복사합니다.
2. ☰ → **Pub/Sub → 구독** → `ticket-worker` → **수정**.
3. **전송 유형**: **푸시**. **엔드포인트 URL**: 복사한 URL.
4. **인증 사용 설정**은 **체크하지 않은 채로** **업데이트**.

**예측.** 이제 티켓이 나올까요?

**어디서 볼까.** ☰ → **Cloud Run** → `ticket-worker` → **모니터링 가능성 → 로그**.

**확인.** `403`과 `The request was not authenticated`가 반복됩니다. 2~3번 보이면 바로 고칩니다(실패가 5번 쌓이면 메시지가 `dead-letter`로 옮겨집니다).
1. 구독 → **수정** → **인증 사용 설정** 체크 → 서비스 계정 `tickets-pubsub-push` → **업데이트**.
2. 1~2분 안에 7단계의 티켓이 발급됩니다. 새로 신청하지 않습니다.

`./lab check 8`

**이유.** `ticket-worker`는 인그레스가 **내부**라서 Pub/Sub의 요청은 들어올 수 있습니다. 하지만 **인증 필요**이므로 서명이 없는 요청은 403입니다. 서명을 켜면 Pub/Sub가 `tickets-pubsub-push`로 서명하고, 이 계정은 `ticket-worker`의 **Cloud Run 호출자**입니다(`./lab iam`). 문을 지나는 것(인그레스)과 들어갈 자격(IAM)은 따로입니다.

> **S3:** 403 로그와 발급된 티켓

**막히면.** 고친 뒤에도 계속 "발급 중"이면 메시지가 이미 `dead-letter`로 갔습니다. 새로 한 번 더 신청합니다. 또는 `./lab skip 8`.

## 9단계. 같은 메시지 다시 보내기 (멱등성) (실험, 10분)

**문제.** Pub/Sub는 메시지를 "최소 한 번" 전달합니다. 같은 메시지가 두 번 올 수 있습니다.

**할 일.** 티켓 ID는 티켓 주소 `/t/티켓_ID`의 마지막 부분입니다.
1. ☰ → **Pub/Sub → 주제** → `registrations` → **메시지** 탭 → **메시지 게시**.
2. 본문: `{"registration_id":"티켓_ID"}` → **게시**.

**예측.** 티켓이 하나 더 생길까요?

**어디서 볼까.** `ticket-worker` → **로그**, 30초쯤 뒤.

**확인.** `skip 티켓_ID (status issued)`. 티켓은 그대로 하나입니다.

**이유.** 받는 쪽이 "이미 발급했나"를 먼저 확인합니다. 같은 일을 여러 번 해도 결과가 같은 성질이 멱등성입니다(`ticket_worker/main.py`의 `issue`).

> **S4:** `skip` 로그

## 10단계. 워커 장애, 재시도, dead letter (실험, 25분)

**문제.** 워커가 고장 나면 신청한 사람들은 어떻게 될까요?

**할 일.**
1. ☰ → **Cloud Run** → `ticket-worker` → **수정 및 새 버전 배포** → **변수 및 보안 비밀** → **변수 추가**: `WORKER_FAIL_RATE` = `1` → **배포**.
2. **수정 버전** 탭에서 새 리비전이 100%인지 봅니다.
3. 브라우저 **시크릿 창**에서 `/events/wiring`을 열고 다른 이메일로 신청합니다.

**예측.** 신청은 성공할까요? 티켓은 어떻게 될까요?

**어디서 볼까.**
- `ticket-worker` → **로그**: 500 응답의 간격
- ☰ → **Pub/Sub → 구독** → `ticket-worker` → **데드 레터 처리** 탭: 4단계에서 넣은 설정
- 3분쯤 뒤 구독 `dead-letter` → **메시지** → **가져오기**(ack 체크 해제)

**확인.** 신청은 성공합니다. 500이 점점 긴 간격으로 반복되다가 멈추고, 메시지가 `dead-letter`에 있습니다.

이제 고칩니다.
1. 같은 화면에서 `WORKER_FAIL_RATE`를 지우고 **배포**. 새 리비전이 100%인지 봅니다.
2. 실패한 메시지를 다시 보냅니다.

   ```bash
   scripts/replay-dead-letters.sh --replay
   ```

3. 티켓이 몇 초 안에 발급됩니다.

**이유.** 신청과 발급이 메시지로 나뉘어 있어서, 워커가 고장 나도 신청은 받습니다. 재시도는 일시적인 실패를 고치고, 간격을 늘려 고장 난 서비스를 몰아붙이지 않습니다. 버그는 재시도로 고쳐지지 않으므로 5번 뒤에는 사람이 봅니다.

> **S5:** 반복되는 500 로그, `dead-letter`에서 기다리는 메시지

**막히면.** 메시지가 2개 이상이면 5분마다 도는 잡이 밀린 티켓을 다시 보낸 것입니다(12단계 이후). 정상입니다.

---

# D3. 이벤트와 예약 작업

## 11단계. Eventarc 트리거 (직접, 실험, 20분)

**문제.** 누가 취소하면 대기 1번에게 자리가 가야 합니다. 취소는 여러 곳에서 일어납니다(신청자, 관리자, 마감 처리). 그곳마다 코드를 넣는 대신, 데이터가 바뀐 것 자체에 반응합니다.

**할 일.**
1. ☰ → **Cloud Run → 서비스**에서 `waitlist-promoter`를 체크 → **권한** → **주 구성원 추가**: `tickets-eventarc@프로젝트_ID.iam.gserviceaccount.com`, 역할 **Cloud Run 호출자** → **저장**.
2. ☰ → **Eventarc → 트리거** → **트리거 만들기**.

   | 칸 | 값 |
   |---|---|
   | 트리거 이름 | `registration-changed` |
   | 트리거 유형 | Google 소스 |
   | 이벤트 제공자 | **Cloud Firestore** |
   | 이벤트 유형 | `google.cloud.firestore.document.v1.updated` (`withAuthContext`가 아닌 것) |
   | 리전 | `asia-northeast3` (자동으로 채워짐) |
   | 필터 1 | `database` = `(default)` (자동으로 채워짐) |
   | 필터 2 (**필터 추가**) | `document`, 연산자 **경로 패턴**, 값 `registrations/{registration}` |
   | 서비스 계정 | `tickets-eventarc` |
   | 이벤트 대상 | Cloud Run, 서비스 `waitlist-promoter`, 경로 `/` |

3. **만들기**. 1분쯤 걸립니다. Pub/Sub 역할을 부여하라는 안내는 무시합니다.

그다음 실험합니다. 새 행사 `promo`: 정원 1, 대기 정원 1.
1. 로그인한 창에서 `/events/promo`에 신청합니다.
2. 시크릿 창에서 다른 이메일로 신청합니다. **대기 1번**이 됩니다.
3. 첫 번째 티켓 화면에서 **신청 취소**.

**예측.** 누가, 무엇을 보고 대기자에게 자리를 줄까요?

**어디서 볼까.** 시크릿 창의 티켓 화면, `waitlist-promoter` → **로그**, Firestore Studio의 `registrations`에서 두 문서의 `status`.

**확인.** 몇 초 안에 대기자가 티켓을 받습니다. `./lab check 11`.

**이유.** 취소로 Firestore 문서가 바뀌면 Eventarc가 그 변경을 `waitlist-promoter`에 전달합니다. `web`은 대기자 처리에 관여하지 않습니다. 경로 패턴 필터 덕분에 `registrations`가 아닌 문서의 변경은 오지 않습니다.

> **S6:** 트리거 화면과 대기자에게 발급된 티켓

**막히면.** 배정이 안 되면 `waitlist-promoter` 로그에서 403을 찾습니다. 1번의 권한이 빠진 것입니다. 또는 `./lab skip 11`.

## 12단계. 잡과 Cloud Scheduler (직접, 실험, 30분)

**문제.** 확인 마감, 알림, 오픈 전 준비처럼 아무도 클릭하지 않는데 해야 하는 일이 있습니다.

**할 일.**
1. `./lab env job`으로 값을 출력합니다.
2. ☰ → **Cloud Run → 작업** → **컨테이너 배포**.

   | 칸 | 값 |
   |---|---|
   | 컨테이너 이미지 URL | `./lab env job`의 `image:` 줄 |
   | 작업 이름 | `housekeeping` |
   | 리전 | `asia-northeast3` |
   | 태스크 수 | 1 |
   | 컨테이너 → **태스크 용량** | 태스크 제한 시간 4분, 실패한 태스크당 재시도 횟수 0 |
   | 컨테이너 → **변수 및 보안 비밀** | 첫 이름 칸에 `./lab env job`의 블록 붙여 넣기 |
   | **보안** 탭 | 서비스 계정 `tickets-housekeeping` |
   | 작업 즉시 실행 | 체크 해제 |

   **만들기**.
3. ☰ → **Cloud Run → 작업**에서 `housekeeping` 체크 → **권한** → **주 구성원 추가**: `tickets-scheduler@프로젝트_ID.iam.gserviceaccount.com`, 역할 **Cloud Run 호출자** → **저장**. 잡에서는 이 역할이 "실행할 수 있음"입니다.
4. `housekeeping` → **트리거** 탭 → **스케줄러 트리거 추가**.
   - 이름 `housekeeping` (제안된 이름을 지우고)
   - 리전 `asia-northeast3`
   - 빈도 `*/5 * * * *`
   - 시간대: `South Korea`로 검색 → **한국 표준시(KST)**. `Seoul`, `Korea`로는 나오지 않습니다.
   - **계속** → 서비스 계정 `tickets-scheduler` → **만들기**.
5. ☰ → **Cloud Scheduler** → `housekeeping` 행의 메뉴 → **강제 실행**.

**예측.** 잡이 성공할까요?

**어디서 볼까.** ☰ → **Cloud Run → 작업** → `housekeeping` → **기록** 탭 → 실행을 열고 **로그**.

**확인.** 실행은 **실패**로 표시되고, 로그에 `pre-warm failed`와 403이 있습니다. 잡이 `web`의 설정을 읽을 권한이 없어서입니다. 13단계에서 고칩니다. 나머지 일(마감, 복구)은 그대로 실행되었습니다. `./lab check 12`.

**마감 처리를 봅니다.** 새 행사 `deadline`: 정원 1, 대기 정원 1.
1. 로그인한 창에서 신청합니다. **참석 확인은 누르지 않습니다.**
2. 시크릿 창에서 다른 이메일로 신청합니다. 대기 1번.
3. `housekeeping` → 위쪽 **실행** 옆 화살표 → **재정의하여 실행**(Execute with overrides) → 컨테이너 인수 `--force-release` → **실행**.

**확인.** 첫 번째 자리가 반환되고, 몇 초 뒤 대기자가 티켓을 받습니다. 다른 행사의 확인하지 않은 자리도 함께 반환됩니다(실습 데이터라 괜찮습니다).

**이유.** 잡은 일을 마치면 끝납니다. 요청을 기다리지 않으므로 서비스가 아니라 잡입니다. 실제 마감 처리는 참석 확인 알림 메일이 나간 뒤에만 자리를 반환하는데, 실습에서는 메일이 꺼져 있어 `--force-release`로 마감 처리만 바로 실행했습니다. 잡이 바꾼 Firestore 문서를 Eventarc가 전달해 대기자에게 자리가 갔습니다. 예약 작업과 이벤트가 이어서 일한 것입니다.

> **S7:** 잡의 실행 기록, 반환된 자리를 받은 대기자의 티켓

**막히면.** Scheduler 실행이 `PERMISSION_DENIED`면 3번의 권한. 시간대를 못 찾으면 `South Korea`로 검색합니다. 또는 `./lab skip 12`.

## 13단계. `./lab warmup` (단축, 설명, 10분)

**문제.** 신청 오픈 직전에 잡이 `web`의 최소 인스턴스를 올려 두어야 첫 신청자가 기다리지 않습니다(25단계). 12단계에서 본 403이 이 권한이 없어서였습니다.

**할 일.**

```bash
./lab warmup
```

만드는 것: 커스텀 역할 `webScaler`(서비스 읽기와 수정, 두 권한만), `web` 서비스 하나에 대한 그 역할, `tickets-web`으로 행동할 권한(act-as).

<details>
<summary>콘솔로 직접 하기</summary>

1. ☰ → **IAM 및 관리자 → 역할** → **역할 만들기**. 제목 `Change web's scaling`, ID `webScaler`, 권한 추가에서 `run.services.get`, `run.services.update` 두 개만. **만들기**.
2. ☰ → **Cloud Run → 서비스**에서 `web` 체크 → **권한** → **주 구성원 추가**: `tickets-housekeeping`, 역할 **Change web's scaling** → **저장**.
3. ☰ → **IAM 및 관리자 → 서비스 계정** → `tickets-web` → **액세스 권한이 있는 주 구성원** → **액세스 권한 부여**: `tickets-housekeeping`, 역할 **서비스 계정 사용자** → **저장**.
</details>

**예측.** 이제 강제 실행하면 성공할까요?

**어디서 볼까.** Cloud Scheduler에서 **강제 실행** → 잡의 **기록**.

**확인.** 실행이 성공합니다. `./lab check 13`.

**이유.** Cloud Run에는 "최소 인스턴스만 바꾸는" 권한이 따로 없어서 필요한 두 권한만 담은 역할을 만들었습니다. 그런데 Cloud Run은 서비스를 바꿀 때마다 그 서비스의 계정으로 행동할 권한(act-as)도 요구합니다. act-as는 그 계정으로 새 코드를 배포할 수도 있게 하므로, 최소 권한 원칙의 의도된 예외입니다. 그래서 이 잡 하나, 이 계정 하나로 범위를 좁혔습니다.

---

# D4. 안전한 변경

## 14단계. 나의 GitHub 복사본 (직접, 10분)

**문제.** 코드를 바꾸면 자동으로 테스트하고 배포하려면, 자신이 push할 수 있는 저장소가 필요합니다.

**할 일.**
1. [github.com/joyrla/gdgoc-tickets-lab](https://github.com/joyrla/gdgoc-tickets-lab) → **Use this template** → **Create a new repository**.
2. Owner: 자신의 개인 계정(조직 아님). 이름 `gdgoc-tickets`. **Private**. **Create repository**.
3. 새 저장소의 **Actions** 탭이 열리는지 봅니다.
4. Cloud Shell에서 복사본으로 옮깁니다. 이제부터는 이 폴더에서 작업합니다.

   ```bash
   cd ~
   gh repo clone 내_GitHub_아이디/gdgoc-tickets
   cd gdgoc-tickets
   ./lab check 14
   ```

**예측.** 포크(Fork)가 아니라 템플릿으로 만드는 이유는 무엇일까요?

**확인.** `./lab check 14`가 `ok`.

**이유.** 포크는 Actions가 꺼진 채로 시작하고, 원본 저장소에 묶여 있습니다. 템플릿 복사본은 독립된 저장소입니다. 실습 설정(`~/.gdgoc-lab`)은 폴더와 따로 있어서 새 폴더에서도 `./lab`이 그대로 동작합니다.

**막히면.** `./lab skip 14`가 복사본을 만들고 `~/gdgoc-tickets`에 받아 둡니다.

## 15단계. 키 없는 로그인 (직접, 단축, 35분)

**문제.** GitHub Actions가 배포하려면 Google Cloud에 로그인해야 합니다. 키 파일을 GitHub에 두면, 새어 나갔을 때 누구나 그 키로 배포할 수 있습니다.

**할 일.**
1. 값을 출력합니다. 저장소 ID(숫자)가 여기 있습니다.

   ```bash
   ./lab env github
   ```

2. ☰ → **IAM 및 관리자 → 워크로드 아이덴티티 제휴** → 풀 만들기.
   - 이름 `github` → **계속**
   - 공급자 선택 **OpenID Connect(OIDC)**, 공급자 이름 `gdgoc-tickets`, 발급기관 URL `https://token.actions.githubusercontent.com`, 대상 **기본 대상** → **계속**
   - 공급자 속성(왼쪽 Google, 오른쪽 OIDC), 4줄:

     | Google | OIDC |
     |---|---|
     | `google.subject` | `assertion.sub` |
     | `attribute.repository` | `assertion.repository` |
     | `attribute.repository_id` | `assertion.repository_id` |
     | `attribute.ref` | `assertion.ref` |

   - **조건 추가**: `./lab env github`의 `attribute condition` 줄 → **저장**
3. 풀 `github` → **액세스 권한 부여** → **서비스 계정 가장을 사용하여 액세스 권한 부여** → 서비스 계정 `tickets-deployer` → **필터와 일치하는 ID만**: 속성 이름 `repository_id`, 값은 저장소 ID → **저장** → 대화상자 **닫기**.
4. 배포 계정의 권한을 줍니다.

   ```bash
   ./lab deployer
   ```

   <details>
   <summary>콘솔로 직접 하기</summary>

   - ☰ → **Artifact Registry → 저장소**에서 `gdgoc-tickets` 체크 → **권한** → **주 구성원 추가**: `tickets-deployer`, **Artifact Registry 작성자**.
   - ☰ → **IAM 및 관리자 → IAM** → **액세스 권한 부여**: `tickets-deployer`, **Cloud Run 개발자**.
   - ☰ → **IAM 및 관리자 → 서비스 계정**에서 `tickets-web`, `tickets-ticket-worker`, `tickets-waitlist-promoter`, `tickets-housekeeping` 각각 → **액세스 권한이 있는 주 구성원** → **액세스 권한 부여**: `tickets-deployer`, **서비스 계정 사용자**.
   </details>

5. GitHub의 복사본 → **Settings → Secrets and variables → Actions** → **Variables** 탭 → **New repository variable**, 3번: `./lab env github`의 `GCP_PROJECT_ID`, `WIF_PROVIDER`, `DEPLOYER_SA`.
6. **Actions** 탭 → 왼쪽 **Sign-in test** → **Run workflow** → Branch `main` → **Run workflow**.

**예측.** 다른 사람이 같은 워크플로를 자신의 저장소에서 실행하면 내 프로젝트에 로그인할 수 있을까요?

**어디서 볼까.** 실행 결과의 **Signed in as the deployer** 단계, ☰ → **IAM 및 관리자 → 워크로드 아이덴티티 제휴** → `github` → 공급자의 조건.

**확인.** 초록색 체크와 `tickets-deployer@...`가 출력됩니다. `./lab check 15`.

**이유.** GitHub은 실행마다 짧게 유효한 토큰을 줍니다. 그 안에 저장소 ID와 브랜치가 들어 있습니다. Google Cloud는 조건(내 저장소 ID, `main`)에 맞는 토큰만 받아 `tickets-deployer`의 권한으로 바꿔 줍니다. 저장소 이름은 지우고 다시 만들 수 있지만 ID는 그렇지 않아서 ID를 씁니다. 키가 어디에도 저장되지 않습니다.

> **S8:** 성공한 Sign-in test 실행

**막히면.**

| 오류 | 원인 |
|---|---|
| `unauthorized_client`, `rejected by the attribute condition` | 조건의 저장소 ID, 또는 `main`이 아닌 브랜치에서 실행 |
| `Permission 'iam.serviceAccounts.getAccessToken' denied` | 3번의 액세스 권한 부여, 또는 그 필터의 ID |
| `run.services.list` 거부 | 4번 `./lab deployer` |

또는 `./lab skip 15`.

## 16단계. 배포 켜기 (실험, 15분)

**문제.** 코드를 바꿀 때마다 손으로 배포하면 실수가 생기고, 배포 중에 사이트가 멈출 수 있습니다.

**할 일.**
1. GitHub 복사본의 **Variables**에 `DEPLOY_ENABLED` = `true` 추가.
2. Cloud Shell(`~/gdgoc-tickets`)에서:

   ```bash
   git commit --allow-empty -m "First deploy" && git push
   ```

3. **Actions** → 방금 실행 → `deploy` 작업의 단계를 차례로 봅니다.

**예측.** 새 리비전이 뜬 뒤에도 7단계의 행사와 신청이 남아 있을까요?

**어디서 볼까.** ☰ → **Cloud Run** → `web` → **수정 버전** 탭: 리비전과 트래픽 비율, 이미지 태그.

**확인.** 새 리비전이 0%로 올라가 검사를 받은 뒤 100%가 됩니다. 이미지 태그가 커밋 SHA입니다. `/events/wiring`의 신청은 그대로입니다. `./lab check 16`.

**이유.** 서버는 아무것도 기억하지 않고 데이터는 Firestore에 있으므로, 리비전이 바뀌어도 잃는 것이 없습니다(2단계). 각 배포는 새 리비전이고, 확인을 통과해야 트래픽을 받습니다.

## 17단계. 테스트에 실패하는 코드 (실험, 10분)

**할 일.**

```bash
echo -e '\n\ndef test_broken():\n    assert 1 == 2' >> tests/test_service.py
git add tests && git commit -m "Break a test" && git push
```

**예측.** 이 코드는 배포될까요?

**어디서 볼까.** **Actions**의 실행, `web`의 **수정 버전** 탭.

**확인.** `test`가 실패하고 `deploy`는 실행되지 않습니다. 리비전은 그대로입니다. 되돌립니다.

```bash
git revert --no-edit HEAD && git push
```

**이유.** 테스트를 통과하지 못한 코드는 이미지도 만들지 않습니다.

> **S9:** 실패한 실행

## 18단계. Cloud Run에서만 실패하는 코드 (실험, 20분)

**할 일.** `cloudshell edit web/events.py`로 열고, `home` 함수 맨 위에 두 줄을 넣습니다.

```python
    if get_settings().on_cloud_run:  # only on Cloud Run, so the tests still pass
        raise RuntimeError("deliberate failure")
```

```bash
git add web && git commit -m "Break on Cloud Run" && git push
```

**예측.** 사이트가 멈출까요?

**어디서 볼까.** **Actions**의 `deploy` 단계, `web`의 **수정 버전** 탭.

**확인.** **Smoke test web's new revision**이 실패하고 **Put everything back**이 실행됩니다. 새 리비전은 0%로 남고, 사이트는 계속 정상입니다.

되돌리고, 콘솔에서 직접 롤백해 봅니다.
1. `git revert --no-edit HEAD && git push`, 배포가 끝날 때까지 기다립니다.
2. `web` → **수정 버전** → **트래픽 관리**. 맨 위(방금 배포)와 그 아래(깨진 것)를 건너뛰고, 그 아래의 정상 리비전을 100%로 → **저장**.
3. `curl -sI 사이트_URL/health | grep -i x-served-by`로 응답한 리비전을 봅니다.
4. 같은 화면에서 최신 리비전을 다시 100%로.

**이유.** 새 리비전은 트래픽 0%로 올라가 자기 주소로 먼저 검사받습니다. 롤백은 빌드 없이 이미 있는 리비전으로 트래픽만 돌리므로 몇 초면 끝납니다.

> **S10:** Put everything back이 실행된 화면, 트래픽 관리 화면

**막히면.** `lint`나 `test`가 실패했다면 붙여 넣은 두 줄의 들여쓰기를 확인합니다.

## 19단계. 시작하지 못하는 버전 (실험, 10분)

**할 일.**
1. `web` → **수정 및 새 버전 배포** → 컨테이너 → **설정** → **컨테이너 명령**: `/bin/false`.
2. 아래의 **이 수정 버전에 트래픽 즉시 제공** 체크 해제 → **배포**.

**예측.** 이 리비전이 준비 완료가 될까요?

**어디서 볼까.** `web`의 **수정 버전** 탭, 컨테이너의 **상태 확인**(시작 프로브).

**확인.** 실패 표시가 있는 리비전이 생기고 트래픽은 0%입니다. `/health`에 응답하지 못해 시작 프로브를 통과하지 못했습니다.

**반드시 되돌립니다.** 되돌리지 않으면 다음 배포도 같은 명령을 씁니다. **수정 및 새 버전 배포** → **컨테이너 명령**을 비우고 → **트래픽 즉시 제공** 체크 → **배포**.

<details>
<summary>명령으로 하기</summary>

```bash
gcloud run services update web --region asia-northeast3 --command=/bin/false --no-traffic --tag broken
gcloud run services update web --region asia-northeast3 --command=""
gcloud run services update-traffic web --region asia-northeast3 --to-latest --remove-tags broken
```
</details>

> **S11:** 실패한 리비전이 보이는 수정 버전 탭

---

# D5. 운영

## 20단계. 접근 제어 확인 (실험, 10분)

**예측.** `ticket-worker`의 주소를 알면 인터넷에서 부를 수 있을까요? QR 파일 주소를 알면 누구나 볼 수 있을까요?

**할 일.**

```bash
curl -s -o /dev/null -w '%{http_code}\n' "$(gcloud run services describe ticket-worker --region asia-northeast3 --format='value(status.url)')/"
```

☰ → **Cloud Storage → 버킷** → `프로젝트_ID-assets` → `tickets/`에서 파일 이름 하나를 복사합니다.

```bash
curl -s -o /dev/null -w '%{http_code}\n' "https://storage.googleapis.com/프로젝트_ID-assets/tickets/파일_이름"
```

**확인.** 첫 번째는 `404`, 두 번째는 `403`.

**이유.** 404는 인그레스 **내부** 때문입니다. 인터넷에서 온 요청은 서비스까지 가지 못합니다. 403은 버킷이 비공개이기 때문입니다. QR은 `web`을 거쳐야 볼 수 있습니다.

> **S12:** 두 출력

## 21단계. 로그로 요청 따라가기 (실험, 15분)

**할 일.** 티켓 화면의 **코드**(예: `CEJ-N45`) 하나를 고릅니다. ☰ → **Logging → 로그 탐색기**에 큰따옴표와 함께 `"티켓_코드"` → **쿼리 실행**.

**예측.** 몇 개 서비스의 로그가 나올까요?

**확인.** `web`의 `signup`과 `ticket-worker`의 `issued ticket`. 신청 하나가 여러 서비스를 지나간 길입니다. 11단계의 티켓이면 `waitlist-promoter`도 나옵니다.

그다음 `web` → **모니터링 가능성 → 측정항목**에서 **요청 수**와 **요청 지연 시간**을 봅니다.

**이유.** 부품이 많으면 기록이 있어야 원인을 찾습니다. 모든 서비스가 같은 코드를 로그에 남겨서 한 번의 검색으로 이어집니다.

> **S13:** 로그 탐색기 결과

## 22단계. 콜드 스타트 (실험, 25분 (대기 16분 포함))

**할 일.** 부하 테스트를 위해 값 세 개를 바꿉니다. 각각 **수정 및 새 버전 배포** → **배포**.

| 위치 | 환경 변수 | 값 | 이유 |
|---|---|---|---|
| `web` | `SIGNUPS_PER_MINUTE_PER_IP` | `5000` | 부하 테스트의 요청이 모두 Cloud Shell 주소 하나에서 나감 |
| `ticket-worker` | `WORKER_DELAY_MS` | `2000` | 티켓마다 2초 지연을 넣어 대기열이 쌓이게 함 |
| 잡 `housekeeping`(**작업 구성 보기 및 수정**) | `PREWARM_INSTANCES` | `0` | 자동 확장을 보려면 사전 준비를 끔 |

잡은 바꾼 뒤 **실행**을 한 번 누릅니다.

**사이트를 연 브라우저 탭을 모두 닫고 16분 이상 기다립니다.** 그다음:

```bash
URL=$(gcloud run services describe web --region asia-northeast3 --format='value(status.url)')
scripts/latency.sh "$URL/health" 5
```

**예측.** 첫 요청과 이후 요청의 시간은 얼마나 다를까요?

**어디서 볼까.** 출력, 그리고 `web`의 **컨테이너 인스턴스 수** 그래프에서 0이 된 구간.

**확인.** 첫 요청이 몇 초, 이후는 0.1초 안쪽. 측정표에 적습니다.

**이유.** 인스턴스가 0이면 첫 요청은 컨테이너 시작과 Python 모듈 로딩을 기다립니다. 0까지 줄어드는 대신 생기는 비용입니다. **시작 CPU 부스트**가 이 시간을 줄입니다.

## 23단계. 신청이 몰릴 때 (실험, 25분)

**할 일.** 새 행사 `rush-a`: 신청 시작 **지금부터 3분 뒤**, 정원 100, 대기 정원 50. 바로 실행합니다. 방문자가 오픈 전에 모여 있다가 카운트다운이 끝나면 1초 안에 신청합니다.

```bash
URL=$(gcloud run services describe web --region asia-northeast3 --format='value(status.url)')
locust -f loadtest/locustfile.py --headless --host "$URL" --event-id rush-a --burst --users 300 --spawn-rate 10 --run-time 6m
```

**예측.** 인스턴스는 몇 개까지 늘어날까요? 100석을 넘겨 발급될까요?

**어디서 볼까.** (그래프는 3~5분 늦게 나타납니다)
- `web` → **측정항목** → **컨테이너 인스턴스 수**
- ☰ → **Pub/Sub → 구독** → `ticket-worker` → **측정항목** → 확인되지 않은 메시지 수
- Firestore Studio → `event_counts` → `rush-a`: `held`(좌석을 가진 신청)와 `issued`(발급된 티켓)

**확인.**
- Locust의 `Signups:` 줄, 응답 시간 표의 POST 행(50%와 95%)
- 대기열이 빈 뒤 `held` = `issued` = 100
- 초당 신청 수의 최댓값:

  ```bash
  gcloud logging read 'jsonPayload.event="signup" AND jsonPayload.event_id="rush-a" AND (jsonPayload.result="pending" OR jsonPayload.result="waitlisted")' --freshness=30m --limit=5000 --format='value(timestamp)' | cut -c1-19 | sort | uniq -c | sort -rn | head -3
  ```

**이유.** Cloud Run은 인스턴스당 동시 요청과 CPU를 보고 인스턴스를 늘립니다. 신청 하나하나는 행사의 좌석 카운터 문서 하나를 트랜잭션으로 고칩니다. 같은 문서를 동시에 고치면 차례로 처리되므로, 좌석은 정확하지만 초당 신청 수에는 한계가 있습니다. 그 한계가 여러분이 잰 값입니다.

> **S14:** 인스턴스 그래프, 대기열 그래프, Locust 결과

## 24단계. 동시성 2 (실험, 15분)

**할 일.**
1. `web` → **수정 및 새 버전 배포** → **인스턴스당 최대 동시 요청 수** `2` → **배포**. 새 리비전이 100%인지 봅니다.
2. 새 행사 `rush-c`: 신청 시작 **1분 뒤**, 정원 100, 대기 정원 50.

   ```bash
   locust -f loadtest/locustfile.py --headless --host "$URL" --event-id rush-c --burst --users 150 --spawn-rate 10 --run-time 3m
   ```

3. 끝나면 동시성을 `40`으로 되돌리고 **배포**.

**예측.** 방문자가 절반인데 인스턴스는 23단계보다 많을까요, 적을까요?

**확인.** 3~5분 뒤 **컨테이너 인스턴스 수**를 23단계와 비교합니다.

**이유.** 인스턴스 하나가 받는 요청이 적으면 같은 부하에 인스턴스가 더 필요합니다. 동시성은 비용과 응답 시간 사이의 선택입니다.

> **S15:** 동시성 2의 인스턴스 그래프

## 25단계. 사전 준비 켜기 (실험, 20분)

**할 일.**
1. 잡 `housekeeping` → **작업 구성 보기 및 수정** → `PREWARM_INSTANCES`를 `3`으로 → **업데이트**.
2. 새 행사 `rush-b`: 신청 시작 **지금부터 10분 뒤**, 정원 100, 대기 정원 50.
3. 잡을 **실행**합니다. 끝나면 `web`의 **YAML** 탭을 새로고침해 `run.googleapis.com/minScale: '3'`을 찾습니다.
4. 신청 시작 3분 전에 23단계의 `locust` 명령을 `--event-id rush-b`로 실행합니다.

**예측.** 23단계와 비교해 인스턴스 수와 응답 시간은 어떻게 다를까요?

**확인.** 측정표의 두 열을 채웁니다.

**이유.** 오픈 시각을 알면 미리 인스턴스를 띄워 둘 수 있습니다. 기다리는 시간은 없어지지만, 요청이 없는 동안에도 비용이 듭니다.

> **S16:** 23단계와 비교한 그래프, Locust 결과

---

# D6~7. 정리

## 26단계. 비용과 일시중지 (직접, 15분)

**문제.** 아무도 접속하지 않아도 비용이 드는 것은 무엇일까요?

**할 일.**
1. ☰ → **결제 → 보고서**. 프로젝트로 필터하고 서비스별로 묶습니다.
2. `web` → **측정항목** → **청구 가능한 컨테이너 인스턴스 시간**.
3. 잡을 멈춥니다: ☰ → **Cloud Scheduler** → `housekeeping` → **일시중지**.
4. 배포를 끕니다: GitHub **Variables**의 `DEPLOY_ENABLED`를 `false`로.

3과 4는 `./lab pause` 한 줄로도 됩니다.

**확인.** `./lab check --report`. 결과가 `~/lab-report.txt`에 저장됩니다.

**이유.** 서비스는 요청이 없으면 0으로 줄어 비용이 없습니다. 잡은 5분마다 하루 288번 실행되므로 일시중지합니다. 프로젝트는 지우지 않습니다. 다음 회차(Terraform)에서 직접 만든 것을 코드로 가져옵니다.

> **S17:** 결제 보고서

## 27단계. 제출과 확인 면담

공지된 설문에 아래를 제출하고, 10분 확인 면담을 예약합니다. 면담에서는 스터디장이 하나를 고장 내고, 여러분이 로그에서 찾아 고치고 설명합니다.

---

# 제출

1. `~/lab-report.txt` (`./lab check --report`)
2. 스크린샷 S1~S17
3. 측정표

   | | 23단계 (사전 준비 끔) | 25단계 (사전 준비 켬) |
   |---|---|---|
   | `web` 인스턴스 최대 수 | | |
   | 신청 응답 중앙값 (50%) | | |
   | 신청 응답 95% | | |
   | 좌석, 대기 | | |
   | 초당 신청 수 최댓값 | | |

   콜드 스타트 첫 요청 / 이후 요청: ____ / ____. 동시성 2의 인스턴스 최대 수: ____.

4. 퀴즈
5. 한 문장: **이 실습은 무엇에 관한 것이었나요?**
6. 피드백 설문(개념별 자신감, 1~5점, 가장 헷갈린 단계)

# 퀴즈

각 2점. 맞는 답이면 1점, 자신의 측정값이나 화면을 근거로 이유까지 쓰면 2점.

1. 7단계: 신청 응답은 왔는데 티켓은 왜 없었나요? 메시지는 어디에 있었나요?
2. 8단계: `ticket-worker`에 요청이 도착했는데 왜 403이었나요? 요청을 들여보낸 설정과, 서명한 뒤 통과시킨 권한은 각각 무엇인가요?
3. 9단계: `ticket_worker/main.py`의 어떤 확인이 두 번째 티켓을 막았나요?
4. 10단계: 워커가 실패하는 동안 신청자가 겪은 일과 겪지 않은 일은? 메시지는 마지막에 어디로 갔나요?
5. 11단계: 대기자에게 자리를 준 것은 누구이고, 무엇이 그 일을 시작했나요? 왜 `web`의 일이 아닌가요?
6. `housekeeping`은 왜 서비스가 아니라 잡인가요?
7. `./lab iam`에서 서비스 계정 하나를 골라, 권한마다 왜 필요한지 쓰세요.
8. 15단계: 다른 사람의 저장소가 내 프로젝트에 배포하지 못하게 막는 것은 무엇인가요?
9. 16단계: 새 리비전 뒤에도 행사와 신청이 남아 있던 이유는?
10. 18, 19단계: 깨진 버전이 사용자에게 닿지 않은 이유는? 롤백이 빠른 이유는?
11. 23단계: 발급된 티켓이 좌석을 넘지 않은 이유(`shared/gcp.py`의 `register`)와, 초당 신청 수가 여러분의 값에서 멈춘 이유는?
12. 23, 24, 25단계의 인스턴스 수를 비교하고 차이를 설명하세요. 사전 준비가 필요 없는 경우를 하나 쓰세요.

# 심화 (선택, 목표만)

일찍 끝났다면 하나를 골라 해 봅니다. 방법은 직접 찾습니다.

- 행사가 꽉 찼을 때 트랜잭션 없이 "마감"을 답하게 바꾸고, 23단계를 다시 측정
- 좌석 카운터를 문서 여러 개로 나누고 다시 측정
- 대기실(신청 앞의 대기열)이나 Redis가 다음 단계가 되는 이유와 각각의 비용을 한 쪽으로 정리
- 10단계의 실패를 잡아냈을 알림 하나 추가 (관측 회차 미리 보기)

# 단축 명령 모음

| 명령 | 하는 일 |
|---|---|
| `./lab start 프로젝트_ID` | 1단계: 도구, GitHub 로그인, API, 이미지 저장소, 이미지 |
| `./lab base` | 3단계 |
| `./lab iam` | 누가 무엇을 할 수 있는지, 계정별 표 |
| `./lab env [web\|job\|github]` | 콘솔과 GitHub에 붙여 넣을 값 |
| `./lab workers` | 6단계 |
| `./lab code` | 최근 로그인 코드 |
| `./lab warmup` | 13단계 |
| `./lab deployer` | 15단계의 배포 계정 권한 |
| `./lab check [단계]` | 만든 것 확인. 단계 없이 실행하면 전부 |
| `./lab check --report` | 제출용 보고서 |
| `./lab skip 단계` | 막힌 단계를 대신 만듦 (2, 4, 5, 8, 11, 12, 14, 15) |
| `./lab pause` | 26단계: Scheduler 일시중지, 배포 끄기 |
| `./lab down` | 실습이 만든 것을 모두 삭제 (Terraform 회차 이후에) |
