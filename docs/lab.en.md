# Cloud Ticketing lab

The application is already finished, so you won't write app code here. One command deploys it to your own Google Cloud project. Then you make the one missing connection yourself and watch what happens on the cloud side in the Console.

**What this lab is for:** in a ticketing service that gets a rush of signups, see for yourself how Cloud Run handles requests, how slow work is moved out of the way, and how the service responds to failures, deploys and growing traffic.

| Core concept | Steps |
|---|---|
| Asynchronous processing (Pub/Sub push subscriptions) | 4 |
| Retries, idempotency, dead letter | 5, 6 |
| Event-driven processing (Eventarc) | 7 |
| Scheduled work (Cloud Scheduler, Cloud Run jobs) | 8 |
| Access control (ingress, service accounts, Secret Manager, keyless deploys) | 9 |
| Data (Firestore transactions and TTL, Cloud Storage) | 10 |
| Logs and metrics | 11 |
| Container images and CI/CD | 12 |
| Revisions, traffic, rollback, startup probes | 13, 14 |
| Cold starts, autoscaling, concurrency, pre-warming | 15 to 18 |
| Cost | 0, 19 |

**Part 1** is steps 0 to 11 and **Part 2** is steps 12 to 19. Before you start, check that you can answer the questions in the [pre-read](lab-preread.en.md).

**How to work through it:** read each "Predict" first and answer it yourself before you run anything. Most actions can be done in the Console, and the equivalent commands are folded underneath. If you skip looking at the screens, you won't be able to do the quiz.

**Console labels** below are in Korean, followed by the English meaning.

## Before you start

| You need | Check |
|---|---|
| A Google Cloud free trial | Remaining days and credit under [Billing](https://console.cloud.google.com/billing). If you signed up on September 22, it ends around December 21 |
| A personal GitHub account | The repository is private and is created in your personal account, not in a company or club organization |
| The lab repository's address | In the study group announcement |

**Cost.** Free trial credit covers this, and you won't be charged unless you upgrade yourself. **Don't click the upgrade button.** If you have no card or your trial has ended, tell the lead and you'll get a separate project.

Move around the Console with the menu at the top left or the search bar. On every screen, **first check that your lab project is selected in the project menu at the top.** What the Console calls 작업 is a Cloud Run **job**.

![Architecture](architecture.png)

# Part 1. Setup and background processing

## Step 0. Project and budget

1. Create a [new project](https://console.cloud.google.com/projectcreate), and note the **project ID** shown under the name.
2. Under **결제 → 예산 및 알림** (Billing → Budgets and alerts), create a budget for the lab project of 12,000 KRW.
3. Open Cloud Shell with the terminal icon at the top, and get the lab repository.

```bash
git clone REPOSITORY_ADDRESS gdgoc-tickets && cd gdgoc-tickets
```

Cloud Shell disconnects after a long idle period. When you reconnect, start with `cd ~/gdgoc-tickets`.

**Why:** a budget tells you about spending, but doesn't stop anything by itself. In step 19 you'll compare it with the real cost.

## Step 1. Install and deploy

```bash
./lab up PROJECT_ID
```

When the GitHub sign-in appears, press Enter and enter the code shown at [github.com/login/device](https://github.com/login/device). This takes 10 to 15 minutes. If `Google Cloud is not ready yet` appears, it retries by itself.

- **Check:** at the end you see `Ready.` and your site's address.

```bash
source ~/.bashrc
./lab check
```

The one `NOT` line at the bottom (the Pub/Sub connection) is expected at this point. You'll fix it in step 4.

| Message | Fix |
|---|---|
| `cannot see project` | Check the project ID for typos (it isn't the project name) |
| `no billing account linked` | Link a billing account to the project under [Billing](https://console.cloud.google.com/billing/projects) |
| `The deploy failed` | Deploy again with `gh workflow run ci.yml --ref main` |

## Step 2. Look at what was created

**Predict:** which service is public on the internet, and who calls `ticket-worker`?

Open [Cloud Run](https://console.cloud.google.com/run) in the Console.

1. Find `web`, `ticket-worker` and `waitlist-promoter` in the list of services, and `housekeeping` in the list of jobs.
2. Open `web` and look at **인그레스** (ingress, which decides where requests may come from) on the **네트워킹** (Networking) tab. Then look at the same tab on `ticket-worker`. `web` is **전체** (all), and `ticket-worker` is **내부** (internal).
3. On `ticket-worker`'s **확장** (Scaling) tab, note the maximum instances and the maximum concurrent requests per instance. Compare with `web`.

## Step 3. Sign in and create your first event

1. At `/login` on your site, enter **the email you use for Google Cloud** and request a code.
2. Email is off, so the code goes to the logs.

```bash
./lab code
```

   If nothing prints, run it again after 30 seconds. Enter the 6 digits at the end on the sign-in page.

3. At `/admin`, click **새 행사 만들기** (new event) and fill it in. All times are Korea time.

| Field | Value |
|---|---|
| 행사 이름, 장소 (name, venue) | Anything |
| 주소 (address) | `wiring` |
| 신청 시작 (signups open) | 2 hours ago |
| 신청 마감 (signups close) | Tomorrow |
| 시작, 종료 (start, end) | The day after tomorrow, start before end |
| 참석 확인 마감 (confirmation deadline) | Between tomorrow and the day after |
| 정원, 대기 정원 (seats, waitlist) | 200, 50 |
| 공개 (published) | Checked |

Later events list only the values that differ. Everything else is the same as this table, and **don't forget to check published**, or the signup page won't open.

## Step 4. Make the missing connection (asynchronous processing)

Sign up at `/events/wiring`. You'll be signed up with your logged-in email.

- **Predict:** the signup finishes right away, but the ticket stays at "**티켓 발급 중**" (issuing).

Find out why in the Console.

1. Under [Pub/Sub subscriptions](https://console.cloud.google.com/cloudpubsub/subscription/list), open `ticket-worker` and click **수정** (Edit). **전송 유형** (delivery type) is **가져오기** (Pull). Compare with the `mailer` subscription.
2. Capture this screen for **screenshot 1**.

The signup request ends in `web`. The work of making the ticket is passed on as a Pub/Sub message, but the `ticket-worker` subscription doesn't know where to send it. The message isn't lost. It waits in the subscription.

**Connect it.**

1. Copy the **URL** at the top of the `ticket-worker` page in Cloud Run.
2. On the subscription's edit screen, change **전송 유형** to **푸시** (Push), and paste it into **엔드포인트 URL** (endpoint URL).
3. Turn on **인증 사용 설정** (enable authentication), and choose `tickets-pubsub-push` under **서비스 계정** (service account). Leave **대상** (audience) blank.
4. Click **업데이트** (Update).

<details>
<summary>Do it with commands</summary>

```bash
URL=$(gcloud run services describe ticket-worker --region asia-northeast3 --format='value(status.url)')
gcloud pubsub subscriptions update ticket-worker --push-endpoint="$URL" \
  --push-auth-service-account="tickets-pubsub-push@$(gcloud config get-value project).iam.gserviceaccount.com"
```
</details>

- **Check:** don't sign up again. Wait, and the ticket from a moment ago is issued.
- **Why does this happen?** `web` published the message and answered right away, and the message waited in the subscription. Once connected, it's delivered and processed.

> **Screenshot 1:** the subscription's delivery type (before and after), and the issued ticket

**Going further:** what's the **메시지 보관 기간** (message retention) on the edit screen? What happens to a message after that?

## Step 5. Send the same message again (idempotency)

Pub/Sub can deliver the same message more than once. Send one on purpose. The ticket ID is the last part of the ticket address, `/t/TICKET_ID`.

**Predict:** will a second ticket appear?

Under [Pub/Sub topics](https://console.cloud.google.com/cloudpubsub/topic/list), open `registrations`, go to the **메시지** (Messages) tab, and click **메시지 게시** (Publish message). Use this as the body:

```json
{"registration_id":"TICKET_ID"}
```

About 30 seconds later, open `ticket-worker` in Cloud Run and go to **모니터링 가능성 → 로그** (Observability → Logs).

- **Check:** you see `skip TICKET_ID (status issued)`, and there's still one ticket.
- **Why:** when delivery is "at least once", the receiver has to handle duplicates safely. Getting the same result however many times an operation runs is called idempotency.

<details>
<summary>Do it with commands</summary>

```bash
gcloud pubsub topics publish registrations --message '{"registration_id":"TICKET_ID"}'
gcloud logging read 'resource.labels.service_name="ticket-worker" AND "TICKET_ID"' --limit 5 --format 'value(timestamp, jsonPayload.message)'
```
</details>

> **Screenshot 2:** the `skip` log

## Step 6. Worker failure, retries, dead letter

Change a setting so that `ticket-worker` fails every request.

1. Open the **컨테이너** (Containers) tab of `ticket-worker` in Cloud Run.
2. Under **변수 및 보안 비밀** (variables and secrets), **환경 변수** (environment variables), click **변수 추가** (add variable) and enter `WORKER_FAIL_RATE` = `1`.
3. Click **다시 배포** (Redeploy) at the top, then **새 버전 배포** (deploy new revision).
4. On the **업데이트 기록** (Revisions) tab, confirm the new revision has 100% traffic. If you sign up before the deploy finishes, the ticket will issue normally.

In an **incognito window**, open `/events/wiring` and sign up with **a different email**. You can't change the email in your signed-in window.

**Predict:** will the signup succeed? What happens to the ticket?

Under `ticket-worker`'s **모니터링 가능성 → 로그**, look at the 500 responses. They repeat at intervals, which is Pub/Sub retrying. On the subscription's **데드 레터 처리** (dead-letter) tab, check the settings. The maximum delivery attempts is 5.

**Wait about 3 minutes**, then check the failed message in the terminal.

```bash
scripts/replay-dead-letters.sh
```

- **Check:** you see `1 messages waiting`. A message that used up its attempts has moved to the dead-letter topic. If it's 0, run it again in a minute. If it's 2 or more, the job that runs every 5 minutes published the stuck ticket again, which is normal.

Now fix it. In the same **환경 변수** screen, delete `WORKER_FAIL_RATE` and **다시 배포**. After the new revision has 100%, send the message again.

```bash
scripts/replay-dead-letters.sh --replay
```

- **Check:** the ticket issues within seconds.

<details>
<summary>Change environment variables with commands</summary>

```bash
gcloud run services update ticket-worker --region asia-northeast3 --update-env-vars WORKER_FAIL_RATE=1
gcloud run services update ticket-worker --region asia-northeast3 --remove-env-vars WORKER_FAIL_RATE
```
</details>

> **Screenshot 3:** the repeating 500s in the logs, and the `1 messages waiting` output

**Going further:** even without replaying, the job that runs every 5 minutes republishes stuck tickets. Read `repair` in `jobs/housekeeping.py`. Why does it wait 5 minutes?

## Step 7. Automatic waitlist promotion (Eventarc)

Create a **new event** `promo`, with 1 seat, 1 waitlist, and signups opening 2 hours ago.

1. In your signed-in window, sign up at `/events/promo` and get the seat.
2. In an incognito window, sign up with a different email. You become **대기 1번** (first on the waitlist).
3. Under [Eventarc triggers](https://console.cloud.google.com/eventarc/triggers), read the provider, event type and destination of `registration-changed`.

**Predict:** when the first signup cancels, who gives the seat to the waiting person, and what do they look at?

4. Cancel on the first ticket's page.
5. Watch the ticket page in the incognito window.

- **Check:** the waiting person gets a ticket within seconds. Look at `waitlist-promoter` under **모니터링 가능성 → 로그**.
- **Why does this happen?** When a cancellation changes a Firestore document, Eventarc passes the change to `waitlist-promoter`. `web` isn't involved, and it works the same however the cancellation happens.

In [Firestore Studio](https://console.cloud.google.com/firestore/databases/-default-/data), check the `status` of both documents in the `registrations` collection.

> **Screenshot 4:** the trigger screen, and the ticket issued to the waiting person

## Step 8. Scheduled work (Cloud Scheduler, Cloud Run jobs)

Unlike a service that answers requests, a job exits when its work is done.

1. Under [Cloud Scheduler](https://console.cloud.google.com/cloudscheduler), read the **빈도** (frequency) and **대상** (target) of `housekeeping`.
2. Choose **강제 실행** (force run) from the row's menu.
3. Under Cloud Run's **작업 → housekeeping → 기록** (Jobs → History), watch the new execution appear, and open it to read its logs.

<details>
<summary>Do it with commands</summary>

```bash
gcloud scheduler jobs run housekeeping --location asia-northeast3
gcloud run jobs executions list --job housekeeping --region asia-northeast3 --limit 3
```
</details>

> **Screenshot 5:** the job's execution history

## Step 9. Access control

**Predict:** if you know `ticket-worker`'s address, can you call it from the internet?

```bash
curl -s -o /dev/null -w '%{http_code}\n' "$(gcloud run services describe ticket-worker --region asia-northeast3 --format='value(status.url)')/"
```

- **Check:** it prints `404`, because **인그레스** on the **네트워킹** tab is **내부** (internal). Pub/Sub can still call it, because it arrives by an internal route.

Now look at these in the Console.

| Where | What to check |
|---|---|
| Cloud Run → each service → **보안** (Security) tab → **서비스 계정** | Each service has a different account |
| IAM 및 관리자 → **서비스 계정** | The accounts starting with `tickets-`, and their descriptions |
| 보안 → [보안 비밀 관리자](https://console.cloud.google.com/security/secret-manager) (Secret Manager) | `ticket-secret` and `session-secret` exist, and their values aren't in the code |
| Cloud Run → `web` → **컨테이너** tab → **환경 변수로 노출된 보안 비밀** | How a secret reaches the app |
| IAM 및 관리자 → [워크로드 아이덴티티 제휴](https://console.cloud.google.com/iam-admin/workload-identity-pools) → `github` | How GitHub Actions signs in with no key file. In the provider's condition, find your repository's numeric ID and `main` |

**Why:** if each service has only the permissions it needs, one being compromised doesn't expose the rest.

> **Screenshot 6:** the `404` output, and `ticket-worker`'s ingress setting

## Step 10. Data

**Firestore.** Open [Firestore Studio](https://console.cloud.google.com/firestore/databases/-default-/data).

1. In the `event_counts` collection, note the numbers in the `wiring` document.
2. Close all incognito windows, open a new one, sign up with a different email from step 6, and watch the numbers change.
3. Under **TTL** in the left menu (a feature that deletes documents automatically after a set time), see which collections expire by `expire_at`.

**Cloud Storage.** Under [Buckets](https://console.cloud.google.com/storage/browser), open `PROJECT_ID-assets`.

1. Find a QR file in `tickets/`. At the top, **공개 액세스** (public access) says **공개 아님** (not public).
2. Read the rule on the **수명 주기** (Lifecycle) tab.

**Predict:** if you know this file's address, can anyone see it?

```bash
curl -s -o /dev/null -w '%{http_code}\n' "https://storage.googleapis.com/PROJECT_ID-assets/tickets/FILE_NAME"
```

- **Check:** it prints `403`. A QR can only be seen through `web`.

> **Screenshot 7:** the `event_counts` document, and the bucket's public access

## Step 11. Logs and metrics

Pick the **code** on a ticket page (for example `CEJ-N45`). In [Logs Explorer](https://console.cloud.google.com/logs/query), enter it with double quotes and click **쿼리 실행** (Run query).

```
"TICKET_CODE"
```

- **Check:** you see `web`'s `signup` log and `ticket-worker`'s `issued ticket` log. That's the path one request took across services.

On `web` in Cloud Run, open **모니터링 가능성 → 측정항목** (Observability → Metrics) and look at request count and request latency.

> **Screenshot 8:** the Logs Explorer result

# Part 2. Deploys, scaling, cost

## Step 12. Container images and CI

1. Under [Artifact Registry](https://console.cloud.google.com/artifacts), open `gdgoc-tickets`. There are four images, tagged with commit SHAs. Open the `Dockerfile` and see how one file makes four images.
2. Open the latest run under **Actions** in your GitHub repository, and check the order: checks, build, deploy.

Break a test on purpose.

```bash
echo -e '\n\ndef test_broken():\n    assert 1 == 2' >> tests/test_service.py
git add tests && git commit -m "Break a test" && git push
```

**Predict:** will this code be deployed?

- **Check:** in Actions, `test` fails and `deploy` doesn't run. Cloud Run's revisions don't change.

Undo it.

```bash
git revert --no-edit HEAD && git push
```

Wait for that run to finish before moving on.

> **Screenshot 9:** the failed Actions run

## Step 13. Revisions, checking a new revision, rollback

On `web` in Cloud Run, open the **업데이트 기록** (Revisions) tab. Each revision shows its share of traffic.

Upload code that passes the tests but fails on Cloud Run. Open the file with `cloudshell edit web/events.py`, and add these two lines at the top of the `home` function.

```python
    if get_settings().on_cloud_run:  # only on Cloud Run, so the tests still pass
        raise RuntimeError("deliberate failure")
```

```bash
git add web && git commit -m "Break on Cloud Run" && git push
```

**Predict:** will the site go down?

- **Check:** in Actions' `deploy`, **Smoke test web's new revision** fails, and **Put everything back** runs. A new revision starts at 0% traffic and is checked at its own URL first. The site stays up, and a 0% revision remains under **업데이트 기록**. If `lint` or `test` failed instead, check the indentation of what you pasted.

Undo it and deploy again.

```bash
git revert --no-edit HEAD && git push
```

When the deploy finishes, roll back by hand in the Console. The top of **업데이트 기록** is the revision you just deployed, and the one below it is the broken one. Go back to **the healthy revision below that**.

1. Click **트래픽 관리** (Manage traffic) on **업데이트 기록**.
2. Give that healthy revision 100% and the rest 0% (they must total 100%), and save.
3. Run `curl -sI SITE_ADDRESS/health | grep -i x-served-by` to see which revision answered. The address is in `./lab check`. It changes within seconds. Also open the home page in your browser to confirm it's healthy.
4. On the same screen, put the latest revision back to 100%.

<details>
<summary>Do it with commands</summary>

```bash
gcloud run services update-traffic web --region asia-northeast3 --to-revisions PREVIOUS_REVISION=100
gcloud run services update-traffic web --region asia-northeast3 --to-latest
```
</details>

**Why is it so fast?** There's no build. It only changes where requests go, to a revision that already exists.

> **Screenshot 10:** the Actions run where Put everything back ran, and the traffic screen

## Step 14. A version that fails to start

On `web`'s **컨테이너** tab, read the **시작 프로브** (startup probe) under **상태 확인** (health checks). The app has to answer `/health` before it gets traffic. Now make a revision that fails on purpose. `/bin/false` is a command that fails immediately, `--no-traffic` gives the new revision no traffic, and `--tag` gives it its own address.

```bash
gcloud run services update web --region asia-northeast3 --command=/bin/false --no-traffic --tag broken
```

**Predict:** will this revision become ready?

- **Check:** the command fails, and a failed revision appears under **업데이트 기록**. The app couldn't answer `/health`, so it didn't pass the startup probe.

**You must undo this step.** Otherwise later revisions are made with the same command.

```bash
gcloud run services update web --region asia-northeast3 --command=""
gcloud run services update-traffic web --region asia-northeast3 --to-latest --remove-tags broken
```

> **Screenshot 11:** the Revisions tab showing the failed revision

## Step 15. Cold start

Change the values used by the next steps in the Console. After each one, click **다시 배포 → 새 버전 배포** at the top.

| Where | Environment variable | Value | Reason |
|---|---|---|---|
| `web` → Containers tab | `SIGNUPS_PER_MINUTE_PER_IP` | `5000` | All load-test requests come from one Cloud Shell address |
| `ticket-worker` → Containers tab | `WORKER_DELAY_MS` | `2000` | A 2-second delay per ticket, so a backlog builds up |

For the job, open **작업 → housekeeping → 작업 구성 보기 및 수정** (view and edit job configuration). On the **컨테이너** tab, under **변수 및 보안 비밀**, change `PREWARM_INSTANCES` to `0`, click **완료** (Done), then **업데이트** (Update) at the bottom. Then click **실행** (Execute) to apply it at once. Pre-warming must be off for you to see autoscaling.

Refresh `web`'s **YAML** tab, and confirm `run.googleapis.com/minScale` is missing or `0`.

<details>
<summary>Do it with commands</summary>

```bash
gcloud run services update web --region asia-northeast3 --update-env-vars SIGNUPS_PER_MINUTE_PER_IP=5000
gcloud run services update ticket-worker --region asia-northeast3 --update-env-vars WORKER_DELAY_MS=2000
gcloud run jobs update housekeeping --region asia-northeast3 --update-env-vars PREWARM_INSTANCES=0
gcloud run jobs execute housekeeping --region asia-northeast3 --wait
```
</details>

**Close every browser tab with the site open, and wait at least 16 minutes.** An open tab keeps sending requests. Then measure.

```bash
URL=$(gcloud run services describe web --region asia-northeast3 --format='value(status.url)')
scripts/latency.sh "$URL/health" 5
```

- **Predict:** the first request takes a few seconds, and later ones under 0.1 s.
- **Why does this happen?** The first request waits for the container to start and the Python modules to load. **시작 CPU 부스트** (startup CPU boost) on the **컨테이너** tab shortens this.

Write your numbers down.

## Step 16. When signups rush in (autoscaling)

Right after that, create a new event at `/admin`: address `rush-a`, signups opening **3 minutes from now**, 100 seats, 50 waitlist. [Locust](https://locust.io) is a load-testing tool that creates virtual visitors. When signups open, run:

```bash
URL=$(gcloud run services describe web --region asia-northeast3 --format='value(status.url)')
locust -f loadtest/locustfile.py --headless --host "$URL" --event-id rush-a --users 300 --spawn-rate 10 --run-time 6m
```

- **Predict:** `web` has a concurrency of 40 and a maximum of 20 instances. How many instances will it reach? Will more than 100 seats be issued?
- **Check:** note the `Signups:` line and the POST row of the "Response time percentiles" table (50% is the median, and 95%). The maximum instance count is the highest point on the graph. Check the graphs **3 to 5 minutes later**, because metrics appear late.
  - Cloud Run → `web` → **모니터링 가능성 → 측정항목:** 컨테이너 인스턴스 수 (container instance count)
  - Pub/Sub → Subscriptions → `ticket-worker` → **측정항목:** unacked messages (messages not yet processed)
- **Why does this happen?** Cloud Run adds instances based on concurrent requests per instance and CPU use. 300 visitors isn't 300 concurrent requests, because each request is short and each visitor only sends one every few seconds. While new instances start, the first signups wait.

> **Screenshot 12:** the instance graph, the backlog graph, and the Locust result

## Step 17. Changing concurrency

**Predict:** if each instance may handle only 2 requests at once, how many instances will it take, even with half the visitors?

1. On `web`'s **확장** tab, change **인스턴스당 최대 동시 요청 수** (maximum concurrent requests per instance) to `2`. Click **다시 배포 → 새 버전 배포**, and confirm the new revision has 100%.
2. Create a `rush-c` event, with signups opening **1 minute from now**, 100 seats, 50 waitlist.
3. Send the load.

```bash
URL=$(gcloud run services describe web --region asia-northeast3 --format='value(status.url)')
locust -f loadtest/locustfile.py --headless --host "$URL" --event-id rush-c --users 150 --spawn-rate 10 --run-time 3m
```

Compare the instance count with step 16 after 3 to 5 minutes. Then set it back to `40` on the same tab, click **다시 배포 → 새 버전 배포**, and confirm the new revision has 100%.

> **Screenshot 13:** the instance graph at concurrency 2

## Step 18. Pre-warming

If you know when the rush will come, you can start instances ahead of time.

1. On the job screen from step 15, change `PREWARM_INSTANCES` to `3`, then click **완료** and **업데이트**.
2. Create a `rush-b` event, with signups opening **10 minutes from now**, 100 seats, 50 waitlist.
3. **실행** (Execute) the job.
4. When it finishes, refresh `web`'s **YAML** tab and find `run.googleapis.com/minScale: '3'`.

**Predict:** compared with step 16, how will the instance count and response times differ?

When signups open, run the two lines from step 16 with `--event-id rush-b`.

- **Why:** pre-warming removes the wait for new instances, but it costs money while there are no requests.

> **Screenshot 14:** a graph to compare with step 16, and the Locust result

## Step 19. Cost and cleanup

**Predict:** what costs money even when nobody visits the site?

First run `./lab check` and copy the output. You'll need it to submit. On `web`, under **모니터링 가능성 → 측정항목**, look at billable container instance time.

```bash
./lab check
./lab down
```

Enter your project ID to start the deletion.

- **Check:** the site no longer loads. It's normal for the `PROJECT_ID-tfstate` bucket to remain listed. Delete it if you won't run the lab again.
- When you're completely done, delete the project under [Manage resources](https://console.cloud.google.com/cloud-resource-manager). The next day, find the largest line under **결제 → 보고서** (Billing → Reports), and compare it with your budget from step 0.

> **Screenshot 15:** the last output of `./lab down`, and the billing report

## Submit

Submit these in the announced form:

1. The `./lab check` output you copied in step 19
2. Screenshots 1 to 15
3. This table

| | Step 16 (pre-warm off) | Step 18 (pre-warm on) |
|---|---|---|
| Maximum web instances | | |
| Signup response, median | | |
| Signup response, 95% | | |
| Seats, waitlist | | |

4. Your answers to the quiz below
5. One sentence: **what was this lab about?**

## Quiz

Each question is worth 2 points: 1 point for the right result, and 2 points if you **explain why, using your own numbers or screens**.

1. In step 4, the signup answered right away, so why was there no ticket? Where was the message in the meantime?
2. In step 5, you sent the same message but no ticket was added. Which check in `issue` in `ticket_worker/main.py` prevented it?
3. In step 6, write down what someone signing up went through while the worker was failing, and what they didn't go through. Where did the message go after using up its attempts?
4. In step 7, who gave the seat to the waiting person, and what started it? What do you gain from `web` not handling this itself?
5. Why is `housekeeping` a job and not a service?
6. What setting caused the `404` in step 9 and the `403` in step 10?
7. 300 people rushed in, but no more tickets were issued than there were seats. What guarantees that? Read `register` in `shared/gcp.py` and answer.
8. In step 13, why didn't the broken version reach users? Why does rollback finish in seconds?
9. Write down the first and later request times from step 15. What was the difference spent waiting for?
10. Compare the instance counts in steps 16, 17 and 18, and explain the differences. Name one situation where pre-warming isn't needed.

## More

These are parts of the app itself and aren't directly about cloud concepts.

<details>
<summary>Pages and backend</summary>

The pages are in `web/templates` and `web/static`, and the API is in the FastAPI routers under `web/`.
</details>

<details>
<summary>QR signing and door check-in</summary>

A QR contains a signature to prevent forgery. See `shared/tokens.py` and the `/checkin` page.
</details>

<details>
<summary>Sign-in and email</summary>

Email codes and Google sign-in are in `web/auth.py`. Email goes through Resend, in `shared/mail.py`. In the lab it's off, and codes are read from the logs.
</details>

<details>
<summary>Running on your laptop</summary>

The same code runs on a laptop with SQLite and direct HTTP calls. See "실행" in the [README](../README.md).
</details>

<details>
<summary>Monitoring, alerts, bot protection</summary>

`production_extras = true` adds uptime checks, alerts, SLOs, reCAPTCHA and backups. Monitoring is covered in a later session. The Google Cloud resources are created with Terraform, which also has its own session.
</details>
