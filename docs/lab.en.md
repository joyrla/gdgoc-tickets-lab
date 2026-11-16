# Cloud Ticketing lab

You put a finished event-signup service into your own Google Cloud project, then sign up and cancel on it yourself and follow where each request goes through the cloud. You write no code.

1. **Setup**: make a project and your own GitHub repository, then build everything with one command.
2. **Connect**: connect GitHub to Google Cloud and the email service to Google Cloud, by hand.
3. **Walkthrough**: cause signups, cancels and a rush in the app, then follow what happens through the emails that really arrive and the Console. A few things you break on purpose and fix.

| | |
|---|---|
| Level | Introductory (200) |
| Time | 70-minute session + about 4 hours over two weeks (in four sittings) |
| Cost | Taken from the free trial credit. A 12,000 won budget alert is set. Real cost is a few thousand won |
| Last checked | 2026-11-16 (updated after the full test run) |

**By the end you can**

- Connect GitHub to Google Cloud without keys, and explain why another repository or branch is refused
- Keep a third-party key in Secret Manager and explain who can read it
- Follow one signup through `web` → Pub/Sub → worker → Firestore → email, in the Console and the logs
- Read a 403, a retry, a dead letter and a failed deploy, and find the one setting behind each
- Compare autoscaling, concurrency, cold start and pre-warm with your own measurements

## Before you start

| You need | |
|---|---|
| A Google account | A personal Gmail account that can use the free trial. School accounts may block projects or billing |
| A GitHub account | Accept the instructor's invitation to the lab repository first ([github.com/notifications](https://github.com/notifications)) |
| A mail key and a sender address | Your instructor sends them in a private message. You use them in Mission 3 |

**Every time you open Cloud Shell,** first go to your repository's folder. Every `./lab` command runs from there.

```bash
cd ~/gdgoc-tickets
```

**More addresses from one inbox.** Gmail delivers mail for `you+anything@gmail.com` to `you@gmail.com`. With `you+b@gmail.com` and `you+c@gmail.com` one inbox can play several attendees; the app treats each as a different person.

**Email limit.** Everyone shares one mail key's limit (100 emails a day). Following this sheet sends about 15 emails per person over two weeks. Don't send more than 10 in one day.

## How to read this

- **The site** is the address `./lab up` prints on its last line (`https://web-...run.app`).
- ☰ is the navigation menu at the top left of the Console. "☰ → **Cloud Run → Services**" means: in ☰, point at **Cloud Run** and click **Services**.
- **Pub/Sub, Eventarc, Cloud Scheduler and Logging are not in the default ☰ list.** Once, open ☰ → **View all products** and click the ☆ on those four rows; they then appear under **Favorite products** at the top of ☰.
- Bold text is a button or field in the Console, on GitHub or on the site. The site is in Korean; its labels are given in Korean with the English meaning. If your Console is in Korean, use the Korean sheet (`lab.ko.md`).
- On every Console screen, first check that the project menu at the top shows your lab project.
- Copy and run the commands as they are. The only value you change is `you@gmail.com` (your Gmail address).

**Each mission** has **Where** (which of the site, the Console, Cloud Shell, GitHub or your inbox you use), **Do**, **Predict**, **Email**, **Where to look**, **Check** and **Why**. Write the prediction in one line before you start. Wrong predictions are fine.

**Submission cues:** **Submit 1** to **Submit 6** are required screenshots; **Optional** ones are up to you. They are collected in [Submission](#submission) at the end.

**When stuck:** after 20 minutes, post the mission number, the `./lab check` output and the error screen in the help thread. If something is broken, running `./lab up` again puts every setting back to the code's version.

## If you know AWS

| AWS | This lab (Google Cloud) |
|---|---|
| Account | Project |
| App Runner, ECS Fargate service | Cloud Run service (`web`, two workers) |
| ECS run-task | Cloud Run job (`housekeeping`) |
| SNS + SQS | Pub/Sub. The topic is like SNS; each subscription is like an SQS queue |
| SQS dead-letter queue | The dead-letter topic and its subscription |
| EventBridge rule | Eventarc trigger |
| EventBridge Scheduler | Cloud Scheduler |
| DynamoDB | Firestore |
| Secrets Manager | Secret Manager |
| IAM role a service assumes | Service account |
| Resource policy (`lambda:InvokeFunction`) | A role granted on the resource (`Cloud Run Invoker`) |
| GitHub OIDC identity provider | Workload Identity Federation |
| CloudFormation stack | Nothing in the Console; the Terraform code and state play that role |

## What gets built

![Architecture](architecture.png)

| Part | What it does |
|---|---|
| `web` (Cloud Run service, public) | Event pages and API. Saves the seat in Firestore, leaves a "make a ticket" message, and answers at once |
| Pub/Sub topic `registrations` and subscription `ticket-worker` | Holds messages and delivers them to the worker. Retries on failure; after 5 failures, moves the message to `dead-letter` |
| `ticket-worker` (service, internal only) | Makes the QR ticket, and sends the emails that arrive on the `emails` topic |
| Eventarc trigger and `waitlist-promoter` (service, internal only) | When a registration changes (a cancel), gives the seat to the first person waiting |
| Cloud Scheduler and `housekeeping` (Cloud Run job) | Every 5 minutes: deadlines, resending stuck tickets, filling free seats, pre-warming before an opening |
| Firestore | Events, registrations, seat counters |
| Secret Manager | The mail key (`smtp-password`) and the app's secret values |
| 8 service accounts | One per part, with only the permissions it needs |
| GitHub Actions (your repository) | On every push to `main`: checks, image builds, deploy |
| Resend (an email service outside Google Cloud) | Sends the real emails |

## The eight key moments

These are the eight moments you learn the most from. The other missions (0 setup, 1 look around, 3 connect email, 12 wrap-up) support them.

| | Moment | Mission | What you learn |
|---|---|---|---|
| 1 | Connect GitHub without keys and watch another branch get refused | 2 | Keyless deploy, the trust condition |
| 2 | Follow one signup through `web` → Pub/Sub → worker → Firestore | 4 | How a whole cloud system fits together, asynchronous work |
| 3 | Connect the queue to the worker yourself and fix the 403 | 5 | The queue keeps messages safe, ingress vs IAM |
| 4 | Break the worker and watch retries and the dead letter | 6 | Failures are kept, not lost; idempotency |
| 5 | Cancel and watch the waiting person get the seat and the email | 7 | Event-driven design |
| 6 | Split traffic to a new revision and roll back; watch broken code get stopped | 8, 9 | Revisions, safe deploys, rollback in seconds |
| 7 | Measure a cold start, then watch pre-warm before an opening | 10 | Scale to zero, cold start, cost |
| 8 | Rush 300 visitors at once and change concurrency | 11 | Autoscaling, concurrency, where the limit is |

## Schedule

| Sitting | Missions | Time |
|---|---|---|
| 1 (session) | 0 Setup, 1 Look around | 70 min |
| 2 | 2 Connect GitHub, 3 Connect email | 50 min |
| 3 | 4 Follow one signup, 5 Connect the queue to the worker, 6 Worker failure and dead letter | 55 min |
| 4 | 7 Cancel and events, 8 Revisions and rollback, 9 Deploy broken code | 50 min |
| 5 | 10 Cold start and pre-warm, 11 The rush, 12 Cost and pause, submission | 70 min |

---

# Part 1. Setup

## Mission 0. Project, budget, your repository, build it all (20 min + 25 min waiting)

**Where:** Console, GitHub, Cloud Shell

**Do.**
1. ☰ → **IAM & Admin → Create a project**. Enter a name and note the **Project ID** under it. **Create**.
2. Select the new project in the project menu at the top.
3. ☰ → **Billing**. If it says no billing account is linked, use **Link a billing account** to link your free trial account.
4. ☰ → **Billing** → left menu **Budgets & caps** → **Create new**.
   - **Definition**: **Alerts only**. Any name. **Next**
   - **Scope**: under **Projects**, tick only your lab project. **Next**
   - **Amount**: target amount `12000`. **Next**
   - **Actions**: defaults (50%, 90%, 100%) → **Finish**
5. Make your own repository. [github.com/joyrla/gdgoc-tickets-lab](https://github.com/joyrla/gdgoc-tickets-lab) → **Use this template** (top right) → **Create a new repository**.
   - **Owner**: your account
   - **Repository name**: `gdgoc-tickets`
   - **Private**
   - **Create repository**
6. Click **Activate Cloud Shell** (>_) at the top right of the Console. Sign in to GitHub, get your repository and build everything.

   ```bash
   gh auth login --web --scopes workflow
   gh repo clone gdgoc-tickets
   cd gdgoc-tickets
   ./lab up
   ```

   - `gh auth login`: press Enter at both questions and at `Press Enter`. Cloud Shell cannot open a browser, so the terminal just waits. In a new tab open [github.com/login/device](https://github.com/login/device), type the 8-character code on screen → **Continue** → **Authorize github**. When the terminal says `Logged in as`, the next line runs. Ignore the clipboard warning (`Failed to copy`).
   - `gh repo clone gdgoc-tickets`: gets `gdgoc-tickets` of the account you signed in with, which is the repository you made in step 5.
   - `./lab up`: shows the name and ID of the project Cloud Shell is using (the yellow text in the prompt) and asks. If it is the project from step 1, type `y`; if not, press Enter, pick the project at the top of the Console and reopen Cloud Shell.

What `./lab up` does: installs tools, turns on APIs, builds four images with Cloud Build, then uses Terraform to create 3 services, a job, the topics and subscriptions, an Eventarc trigger, the schedule, 8 service accounts, 4 secrets and about 30 permissions. It takes 20 to 25 minutes. Do Mission 1 while you wait.

**Check.** The last line shows your site's address. Opening it shows an empty event list.

**Why.** A budget only sends alerts; it does not stop anything. **Do not click "Upgrade to a full account".** Building each part in the Console is mostly filling in forms, so a command does it. This lab spends its time connecting, using, breaking and measuring the parts. Building them is the topic of the next session (Terraform).

**Stuck?**

| Message | Fix |
|---|---|
| `No project is selected`, or another project's name | Pick the lab project at the top of the Console and reopen Cloud Shell |
| `no billing account linked` | Step 3 |
| No **Use this template** button | Check that you accepted the invitation to the lab repository |
| `Could not resolve to a Repository` | Step 5 not done yet, or the name is not `gdgoc-tickets`, or the owner is another account |
| `Google Cloud is not ready yet` | Common in a new project. The command retries by itself a minute later |
| Cloud Shell disconnected (it shuts down after 40 minutes without input) | Reopen it and run `cd ~/gdgoc-tickets && ./lab up`; it keeps what was built and continues. If it asks to unlock, type `y` |

## Mission 1. Look around (15 min, while `./lab up` runs)

**Where:** Console

Look at what is being built. Parts appear in the Console as `./lab up` finishes them.

**Do.** Find the answers to these five questions in the Console and write them down.

1. ☰ → **Cloud Run → Services** → `web` → **Security** tab: which service account does `web` run as?
2. ☰ → **Pub/Sub → Topics** → `registrations` → **Permissions** on the right: who may send messages to this topic?
3. ☰ → **Pub/Sub → Subscriptions** → `ticket-worker` → **Details**: what is the delivery type, and where does a message go after how many failures?
4. ☰ → **Cloud Run → Services** → tick `ticket-worker` → **Permissions**: who may call `ticket-worker`? Which subscription uses that account right now? (Hint: the `mailer` subscription in Pub/Sub)
5. ☰ → **Eventarc → Triggers** → `registration-changed`: which changes does it react to?

<details>
<summary>Check your answers</summary>

1. `tickets-web`. Every service runs as its own service account.
2. `tickets-web`, `tickets-waitlist-promoter`, `tickets-housekeeping` (Pub/Sub Publisher). Signups, waitlist promotions and resent stuck tickets all send messages to this topic.
3. **Pull**. After 5 failures a message moves to the `dead-letter` topic. Mission 5 switches it to Push.
4. `tickets-pubsub-push` (Cloud Run Invoker). Right now the `mailer` subscription (email) signs as this account to call `ticket-worker`. The `ticket-worker` subscription is still Pull, so it doesn't use it yet.
5. A Firestore document update (`document.v1.updated`), only for documents under `registrations/`. The change goes to `waitlist-promoter`.
</details>

`./lab iam` shows every account's permissions and the reason for each in one table.

**Why.** The Console shows what exists now, one part at a time. How the parts connect only shows when you follow it, as in these five questions. The code (`infra/*.tf`) holds what should exist and why.

---

# Part 2. Connect

You connect two outside services to what was built: GitHub (push code, get a deploy) and Resend (send email). Neither connection puts a key in the code.

## Mission 2. Connect GitHub to Google Cloud (30 min)

**Where:** Cloud Shell, GitHub, Console

**Problem.** To deploy to your project, GitHub Actions must sign in to Google Cloud. A service account key stored in GitHub would let anyone deploy the moment it leaked.

**Do.**
1. Build the keyless sign-in. At the end it prints three GitHub variables and their values.

   ```bash
   ./lab github
   ```

2. Your repository (the address in the `./lab github` output) → **Settings** → left **Secrets and variables → Actions** → **Variables** tab → **New repository variable**. Add `GCP_PROJECT_ID`, `WIF_PROVIDER` and `DEPLOYER_SA` one at a time, copying the values from the `./lab github` output. They are not secret, so they go in the **Variables** tab, not **Secrets**.
3. Wait two minutes, then **Actions** → left **Sign-in test** → **Run workflow** → **Run workflow**.

**Predict.** You stored no key at all. Will it sign in?

**Where to look.**
- The run → the **Signed in as the deployer** step
- ☰ → **IAM & Admin → Workload Identity Federation** → `github` → provider `gdgoc-tickets` → **Attribute condition**

**Check.** A green tick. It signed in as `tickets-deployer`. The attribute condition holds your repository's ID and `refs/heads/main`. `./lab check github`.

4. Try another branch.

   ```bash
   git switch -c try-branch && git push -u origin try-branch
   ```

   **Actions** → **Sign-in test** → **Run workflow** → **Branch** `try-branch` → **Run workflow**.

**Predict.** Same repository, same code. Will it sign in?

**Check.** It fails. Take a screenshot of the failed step's error (**Submit 1**). Then delete the branch.

```bash
git switch main && git push origin --delete try-branch
```

5. Turn deploys on. **Variables** tab → **New repository variable**: `DEPLOY_ENABLED` = `true`.
6. Your first deploy. Change one sentence on the home page and push it.

   ```bash
   cloudshell edit web/templates/home.html
   ```

   On line 7, replace `행사를 찾아 신청하고 QR 티켓으로 입장하세요.` with any sentence, and save (Ctrl+S).

   ```bash
   git commit -am "First deploy" && git push
   ```

**Where to look.** **Actions** → the new run (**CI/CD**) → the steps of the `deploy` job. ☰ → **Cloud Run** → `web` → **Revisions** tab.

**Check.** About 7 minutes later every job is green and the site's home page shows your sentence. `web`'s new revision has 100%. `./lab check deploys`.

**Why.** For every run GitHub issues a short-lived token that contains the repository ID and the branch. Google Cloud accepts only tokens that match the attribute condition (your repository ID, `main`) and exchanges them for a short-lived `tickets-deployer` token. With no stored key, there is no key to leak or rotate. The same repository on another branch is refused, and someone else's repository has another ID. The three variables only say where to sign in.

**Stuck?**

| Symptom | Fix |
|---|---|
| `./lab github` says `not your own copy` | Mission 0, steps 5 and 6. Run it from your repository's folder, not from a clone of the template |
| The sign-in test fails with `getAccessToken` | The permission is still spreading. Run it again in two minutes |
| The `deploy` job is skipped | `DEPLOY_ENABLED` must be exactly `true` |
| `git push` is refused | Sign in again with `gh auth login --web --scopes workflow` |

## Mission 3. Connect email (20 min)

**Where:** Console, Cloud Shell, the site, your inbox

Email is off for now: every email the app would send only shows as `not sent` in the logs. You use the **mail key** and **sender address** your instructor sent in a private message. The key is like a password: never put it in chat, code or a screenshot.

**Do.**
1. ☰ → **Security → Secret Manager** → `smtp-password` → **Versions** tab → **New version** → paste the mail key as the value → add it.
2. `mail-from` → **New version** → the sender address → add it.
3. Turn email on.

   ```bash
   ./lab mail on
   ```

4. **In the app.** The site → **로그인** (Sign in) at the top → **이메일** (Email): the Gmail address of the Google account that ran `./lab up` → **코드 받기** (Get code).

**Email.** `[Cloud Ticketing] 인증 코드 123456` (sign-in code). Type the code into **인증 코드** (Code) and click **확인** (Confirm). **관리** (Admin) appears in the top menu: the account that ran `./lab up` is an organizer.

**Predict.** Can `web` read the mail key?

**Where to look.** `smtp-password` → **Permissions** tab. ☰ → **Cloud Run** → `ticket-worker` and `web` → **Containers** tab → **Variables & Secrets**.

**Check.** Only `tickets-ticket-worker` can read the key, and `web` has no mail key attached. `./lab check mail`.

**Why.** A third-party key goes in Secret Manager, not in code or a plain variable. To change the key you add a new version, and the service reads it when it starts. Even the sign-in email is not sent by `web`: `web` leaves a message on the `emails` topic, the `mailer` subscription delivers it to `ticket-worker`, and the worker sends it through Resend. Only that worker may read the key, so a break-in to `web` would not leak it.

> **Optional:** the code email in your inbox (code hidden), `smtp-password`'s **Permissions** tab

---

# Part 3. Walkthrough

Now you use the app. **In the app** lists the buttons to press on the site; **Email** is what should then arrive in your inbox. An email that does not arrive is a result too: find out why in the Console and the logs. Every subject starts with `[Cloud Ticketing]`.

## Mission 4. Follow one signup (20 min)

**Where:** the site, your inbox, Console

**In the app.**
1. **관리** (Admin) at the top → **새 행사 만들기** (New event).
   - **행사 이름** (Event name): `연결 확인`
   - **주소** (Address): `wiring`
   - **장소** (Venue): `온라인`
   - Leave the dates and seats as they are
   - Tick **공개** (Published) at the bottom → **행사 만들기** (Create event)
2. **행사 페이지** (Event page) → **신청하기** (Sign up). Fill in **이름** (Name) if it is empty, tick **개인정보 수집 및 이용에 동의합니다** (I agree to the privacy terms) → **신청하기**. The email is your signed-in Gmail.
3. **티켓 보기** (View ticket).

**Predict.** Will a confirmation email arrive? Will the ticket page show a QR code?

**Email.** None.

**Where to look.**
- ☰ → **Firestore** → `(default)` → **Firestore Studio** → `registrations`: your new document and its `status`
- ☰ → **Pub/Sub → Subscriptions** → `ticket-worker` → **Messages** tab → **Pull**. Leave **Enable ack messages** unticked. Pull only once (each pull counts as a delivery attempt).

**Check.** The ticket stays at **티켓 발급 중** (Issuing your ticket), and no email arrives. One `{"registration_id": ...}` message is waiting in the subscription.

**Why.** `web` saved the seat in Firestore, left a message and answered right away. The subscription is **Pull** for now, so it just keeps the message until someone takes it. Nothing is lost. The confirmation email is sent by the worker that issues the ticket, so while the message has not reached the worker there is no email either. Because signup and ticketing are split, signups keep working even when ticketing is slow or stopped.

> **Optional:** the waiting message and the "issuing" ticket page

## Mission 5. Connect the queue to the worker (15 min, by hand)

**Where:** Console, your inbox

This is the connection you make in the Console yourself.

**Do.**
1. ☰ → **Cloud Run → Services** → copy the **URL** of `ticket-worker`.
2. ☰ → **Pub/Sub → Subscriptions** → `ticket-worker` → **Edit**.
3. **Delivery type**: **Push**. **Endpoint URL**: the URL you copied. Leave **Enable authentication** **unticked** → **Update**.

**Predict.** Will the ticket and the email come now?

**Where to look.** ☰ → **Cloud Run** → `ticket-worker` → **Observability** tab, logs.

**Check.** `403` and `The request was not authenticated` repeat. Still no email. When you see it 2 or 3 times, take a screenshot of the log (**Submit 2**) and fix it right away. After 5 failures the message moves to `dead-letter`.
1. Subscription → **Edit** → tick **Enable authentication** → **Service account** `tickets-pubsub-push` → **Update**.
2. Wait for your Mission 4 signup. Do not sign up again.

**Email.** Within a minute or two of the fix: `신청 완료: 연결 확인` (signup complete). Its link opens the ticket, now with a QR code.

`./lab check push`

**Why.** `ticket-worker`'s ingress is **Internal**, so requests from Pub/Sub may come in (from the internet they get 404). But it requires authentication, so an unsigned request gets 403. With authentication on, Pub/Sub signs as `tickets-pubsub-push`, which holds **Cloud Run Invoker** on `ticket-worker`. Getting through the door (ingress) and being allowed in (IAM) are separate.

> **Submit 2 screenshot:** the `403` log (before the fix), the ticket with its QR code (after)

**Stuck?** If no email comes and the ticket stays "issuing" after the fix, the message already moved to `dead-letter`. Send it back with the replay in Mission 6.

## Mission 6. Worker failure and dead letter (20 min)

**Where:** Console, the site (private window), your inbox, Cloud Shell

**Problem.** If the worker breaks, what happens to the people signing up?

**Do.**
1. ☰ → **Cloud Run** → `ticket-worker` → **Containers** tab → **Variables & Secrets** → **Add variable**: `WORKER_FAIL_RATE` = `1`.
2. Top right **Review changes and redeploy** → check the changed line → **Deploy changes**.

**In the app.** In a browser **private window**, open the site → **연결 확인** → **신청하기** → any **이름**, **이메일** `you+b@gmail.com` → tick the agreement → **신청하기** → **티켓 보기**.

**Predict.** Will the signup succeed? What happens to the ticket and the email?

**Email.** None before the fix.

**Where to look.**
- `ticket-worker` logs: `simulated failure` and `500`
- Subscription `ticket-worker` → **Dead lettering** tab: where failed messages go
- 2 to 3 minutes later, subscription `dead-letter` → **Messages** → **Pull** (**Enable ack messages** unticked)

**Check.** The signup succeeds. `500` repeats a few times and stops, and the message is in `dead-letter`. Take both screenshots before fixing (**Submit 3**).

Now fix it.
1. In the **Containers** tab, delete `WORKER_FAIL_RATE` → **Review changes and redeploy** → **Deploy changes**.
2. Wait a minute, then send the failed message back (a message you pulled stays hidden for one minute).

   ```bash
   scripts/replay-dead-letters.sh --replay
   ```

**Email.** Seconds after the replay, `신청 완료: 연결 확인` for `you+b@gmail.com`. A few minutes later, look for `skip ... (status issued)` in the logs.

**Why.** Because signup and ticketing are split by a message, signups keep working while the worker is broken. Retries fix short failures; a failure that retries cannot fix stays in `dead-letter` after 5 tries for a person to look at. The `skip` line is the job, which runs every 5 minutes, sending the stuck ticket once more. Even when the same message arrives twice, the worker first checks "did I already issue this?", so there is still one ticket and one email (idempotency).

> **Submit 3 screenshot:** the repeated `500` logs and the message waiting in `dead-letter` (both before the fix)

## Mission 7. Cancel and events (15 min)

**Where:** the site (normal and private windows), your inbox, Console

**Problem.** When someone cancels, the first person waiting should get the seat. Cancels happen in many places: the attendee, an organizer, the deadline job.

**In the app.**
1. Normal window: **관리** → **새 행사 만들기**. **행사 이름** `대기 배정 확인`, **주소** `promo`, **장소** `온라인`, **정원** (Seats) `1`, **대기 정원** (Waitlist) `1`, tick **공개** → **행사 만들기**.
2. Normal window: **행사 페이지** → **신청하기** → tick the agreement → **신청하기** → **티켓 보기**. Keep this tab open.
3. Private window: the site → **대기 배정 확인** → **대기 신청하기** (Join the waitlist) → **이메일** `you+c@gmail.com` → tick the agreement → **대기 신청하기** → **티켓 보기**. It shows **대기 1번** (waitlist #1).
4. On the normal window's ticket page, at the bottom: **신청 취소** (Cancel registration) → "신청을 취소할까요?" (Cancel?) → **OK**.

**Predict.** Who gives the seat to the waiting person, and what triggers it?

**Email.**

| When | To | Subject | Sent by |
|---|---|---|---|
| After 2 | `you@gmail.com` | `신청 완료: 대기 배정 확인` (signup complete) | `ticket-worker`, after issuing the ticket |
| After 3 | `you+c@gmail.com` | `대기 신청 완료: 대기 배정 확인` (on the waitlist) | `web` |
| After 4 | `you@gmail.com` | `신청 취소: 대기 배정 확인` (cancelled) | `web` |
| Seconds after 4 | `you+c@gmail.com` | `자리 배정: 대기 배정 확인` (you got a seat) | `ticket-worker`, after issuing the waiting person's ticket |

**Where to look.** The private window's ticket page (reload it), `waitlist-promoter` logs, and the `status` of both documents in Firestore Studio → `registrations`.

**Check.** Within seconds the private window's ticket shows a QR code and the `자리 배정` email arrives.

**Why.** The cancel changes a Firestore document; Eventarc delivers that change to `waitlist-promoter`. The promoter gives the seat to the first person waiting and leaves a message on the `registrations` topic, so the ticket and the `자리 배정` email go out the same way as in Missions 4 to 6. `web` knows nothing about the waitlist. Because the system reacts to the data change itself, a cancel from anywhere is handled in one place. If delivery fails, the job that runs every 5 minutes fills free seats anyway: events for speed, a periodic sweep for correctness.

> **Optional:** the `자리 배정` email and the `waitlist-promoter` log

## Mission 8. Revisions and rollback (15 min)

**Where:** Console, Cloud Shell

**Do.**
1. ☰ → **Cloud Run** → `web` → **Containers** tab → **Add variable**: `LAB_NOTE` = `v2`.
2. **Review changes and redeploy** → **untick** **Serve this revision immediately** at the bottom → **Deploy changes**.
3. `web` → **Revisions** tab.

**Predict.** How many users see the new revision?

**Check.** There is a new revision with 0% of traffic. The revision GitHub deployed in Mission 2 is in the list too.

4. **Revisions** → **Manage traffic**: new revision 50%, previous revision 50% → **Save**.
5. See which revision answers, ten times.

   ```bash
   URL=$(gcloud run services describe web --region asia-northeast3 --format='value(status.url)')
   for i in $(seq 10); do curl -sI "$URL/health" | grep -i x-served-by; done
   ```

   Both revision names appear, mixed. Take a screenshot (**Submit 4**).
6. Roll back: in **Manage traffic**, set the previous revision to 100% → **Save**. Now only one name appears.
7. Finally, set the latest revision back to 100%.

**Why.** Every deploy creates a new revision, and how much traffic it gets is a separate decision. A rollback just moves traffic back to a revision that already exists, with no build, so it takes seconds. In Mission 9 the automatic deploy uses the same idea to stop a broken version.

> **Submit 4 screenshot:** the **Revisions** tab split 50/50 and the `curl` output

## Mission 9. Deploy broken code (20 min)

**Where:** Cloud Shell, GitHub, Console, the site

**Do.**
1. Add code that fails only on Cloud Run. Open `cloudshell edit web/events.py`, add these two lines at the top of the `home` function, and save.

   ```python
       if get_settings().on_cloud_run:  # only on Cloud Run, so the tests still pass
           raise RuntimeError("deliberate failure")
   ```

   ```bash
   git commit -am "Break on Cloud Run" && git push
   ```

**Predict.** Will the site go down?

**Where to look.** Your repository's **Actions** → the new run → the steps of the `deploy` job, and `web`'s **Revisions** tab.

**Check.** The new revision starts at 0%, fails at **Smoke test web's new revision**, and **Put everything back** runs. The site's home page keeps working.

2. Revert it and watch a good deploy.

   ```bash
   git revert --no-edit HEAD && git push
   ```

   The new revision passes its check at 0%, then gets 100%. The image tag is the commit SHA.

**Why.** A deploy sends traffic to a new revision only after it passes a check at 0%; if it fails, traffic stays on the previous revision. GitHub Actions does in order what you did by hand in Mission 8, so broken code is stopped before it reaches users.

> **Optional:** the failed **Smoke test web's new revision** step and the **Revisions** tab at that moment

## Mission 10. Cold start and pre-warm (25 min, with waiting)

**Where:** Cloud Shell, Console

**Cold start.** Do this first in the sitting, when the site has not been opened for more than 15 minutes.

```bash
./lab coldstart
```

**Predict.** How different are the first request and the ones after it?

**Check.** The first request takes seconds; the next ones under 0.1 s. Write both in the measurement table.

**Pre-warm.**
1. Create an event whose signups open in 20 minutes. It is the same as **새 행사 만들기** in the admin pages with **신청 시작** (Signups open) set 20 minutes ahead.

   ```bash
   ./lab event opening --opens-in 20
   ```

2. ☰ → **Cloud Scheduler** → tick the `housekeeping` row → **Force run**, so the job runs now instead of in up to 5 minutes.
3. ☰ → **Cloud Run → Jobs** → `housekeeping` → **History** tab → the run you just started → logs.

**Predict.** What will the job do to `web`?

**Check.** The log says `pre-warm: web minimum instances 0 → 3`. In `web` → **Observability**, the instance count graph shows 3 instances. An hour after the opening, the job sets it back to 0.

**Why.** With 0 instances, the first request waits for a container to start. Scaling to zero means no cost at night; the price is a slow first request. When the opening time is known, the job starts instances ahead of time. The wait disappears, but idle instances cost money. The job may change `web`'s settings because of a custom role with just two permissions (read and update; see `housekeeping` in `./lab iam`).

> **Submit 5 screenshot:** the `./lab coldstart` output, the graph with 3 instances before the opening

## Mission 11. The rush (25 min)

**Where:** Cloud Shell, Console

**Do.**
1. Create an event that opens in 3 minutes (100 seats, waitlist 50) and start the load test right away. 300 visitors keep the event page open before the opening and press **신청하기** the moment it opens.

   ```bash
   ./lab event rush-a --opens-in 3 --seats 100 --waitlist 50
   ./lab load rush-a
   ```

**Predict.** How many instances will there be at most? Will more than 100 tickets be issued?

**Email.** None. The visitors' addresses are `@example.com`, a domain reserved for testing, so nothing is sent even with email on; the logs say `test address, not sent`.

**Where to look.** (graphs appear 3 to 5 minutes late)
- `web` → **Observability**: instance count, request latency
- Subscription `ticket-worker` → **Metrics**: unacked messages
- Firestore Studio → `event_counts` → `rush-a`: `held` (registrations holding a seat) and `issued` (tickets issued)

**Check.** Locust's `Signups:` line and response-time table, and `held` = `issued` = 100. Write them in the measurement table and take the screenshots (**Submit 6**). Because the event opens within minutes, pre-warm (Mission 10) may have started 3 instances already; look at how many more than 3 the graph shows.

2. Measure again with another concurrency. `web` → **Containers** tab → **Maximum concurrent requests per instance** `2` → **Review changes and redeploy** → **Deploy changes**.

   ```bash
   ./lab event rush-c --opens-in 1 --seats 100 --waitlist 50
   ./lab load rush-c --users 150 --minutes 3
   ```

3. When it ends, set concurrency back to `40`.

**Predict.** With half the visitors, will there be more instances than the first time, or fewer?

**Why.** Cloud Run adds instances by looking at concurrent requests per instance. With lower concurrency, the same load needs more instances. Every signup changes the event's single seat-counter document in a transaction, so seats are exact but signups per second have a ceiling. More instances do not raise it.

> **Submit 6 screenshot:** `web`'s instance count graph, the Locust result (`Signups:` line and response-time table)

## Mission 12. Cost and pause (15 min)

**Where:** Console, Cloud Shell

**Do.**
1. ☰ → **Billing → Reports**. Filter by your project and group by service. Costs appear about a day late.
2. See how far your Console changes are from the code.

   ```bash
   ./lab drift
   ```

3. Pause the lab.

   ```bash
   ./lab pause
   ./lab check --report
   ```

**Why.** With no requests, the services scale to zero and cost nothing. The job runs every 5 minutes, 288 times a day, so it is paused. `./lab pause` also turns GitHub's `DEPLOY_ENABLED` off. The differences `./lab drift` shows are where the next session (Terraform) starts: Console changes are not in the code, and applying the code again (`./lab up`) removes them. Do not delete the project. Your instructor revokes the mail keys when the lab ends.

> **Optional:** the billing report (filtered by project, grouped by service)

---

# Submission

Upload to the announced form. **Required** items are graded; **optional** ones are not.

## Required 1. Six key concepts

One screenshot and one question per concept. Three to five sentences per answer is enough.

**Scoring:** 3 points per concept. Screenshot 1 point, answer 2 points (1 for a correct answer, 2 if the reason is backed by your own screenshot or measurements).

**1. Keyless deploy (Mission 2)**
- Screenshot: **Submit 1**. The failed Sign-in test on `try-branch`
- Question: what stops someone else's repository, or another branch, from deploying to your project? Why does GitHub not need to store a key?

**2. Service accounts and IAM (Mission 5)**
- Screenshot: **Submit 2**. The `403` in `ticket-worker`'s logs (before the fix), the ticket with its QR code (after)
- Question: which setting let the request in, and which one refused it with 403? Which account, with which role, let it through?

**3. Pub/Sub and asynchronous work (Mission 6)**
- Screenshot: **Submit 3**. The repeated `500` logs, the message waiting in `dead-letter`
- Question: while the worker was failing, what did the person signing up experience, and what did they not (the signup page, the ticket, the email)? Where did the message end up, and why there?

**4. Revisions and safe deploys (Mission 8)**
- Screenshot: **Submit 4**. The **Revisions** tab split 50/50 and the `curl` output
- Question: who sees a revision with 0% of traffic? Why does a rollback take only seconds?

**5. Cold start, pre-warm, cost (Mission 10)**
- Screenshot: **Submit 5**. The `./lab coldstart` output, the graph with 3 instances before the opening
- Question: why was the first request slow? How does pre-warm prevent it, and what does it cost? Name one case where pre-warm is not needed.

**6. Autoscaling and concurrency (Mission 11)**
- Screenshot: **Submit 6**. The instance count graph, the Locust result
- Question: how many instances did `web` reach, and why? What changed at concurrency 2? Why did signups per second stop rising even as instances were added?

## Required 2. Also hand in

1. `~/lab-report.txt` (from `./lab check --report` in Mission 12)
2. The measurement table

   | | Concurrency 40 (`rush-a`) | Concurrency 2 (`rush-c`) |
   |---|---|---|
   | Most `web` instances | | |
   | Signup response, median (50%) | | |
   | Signup response, 95% | | |
   | Most signups per second | | |

   Cold start, first request / later requests: ____ / ____.

3. One design question: **if ten times as many people signed up at the opening, what would hit its limit first, and what would you change?** Base it on your own measurements.
4. The feedback form (confidence per concept, 1 to 5, and the most confusing mission)

## Optional

| Mission | Concept | Question |
|---|---|---|
| 1 | The parts | Your five answers. Which connection was hard to see from the Console alone? |
| 3 | Secret Manager | Which account can read the mail key? If the key leaked, what would you do? |
| 4 | Pull subscription | The signup answered, so why were there no ticket and no email? Where was the message? |
| 6 | Idempotency | Why is there one ticket and one email even if the same message arrives twice? |
| 7 | Eventarc | Who gave the seat to the waiting person, and what started it? Of the four emails, why did `web` send some and the worker the others? |
| 9 | Staged deploy | Why did the broken revision never reach users? |
| 10 | Jobs and Cloud Scheduler | Why is `housekeeping` a job and not a service? |
| 12 | Drift | Where did the differences in `./lab drift` come from? |

# Further (optional, goals only)

- When the event is full, answer "full" without a transaction, and measure Mission 11 again
- Split the seat counter across several documents and measure again
- Add one alert that would have caught Mission 6's failure
- Find Mission 5's subscription change in the Terraform code (`infra/events.tf`) and write down how to make it in code instead of the Console

# Shortcuts

All run from `~/gdgoc-tickets`.

| Command | What it does |
|---|---|
| `./lab up` | Build everything. Run it again to put the code's settings back |
| `./lab iam` | Every account's permissions and why |
| `./lab github` | Build the keyless sign-in; print the three variables to add on GitHub |
| `./lab mail on`, `./lab mail off` | Turn real email on or off |
| `./lab event ID [--opens-in MIN] [--seats N] [--waitlist N]` | Create a published event (same as **새 행사 만들기** in the admin pages) |
| `./lab load EVENT_ID [--users N] [--minutes M]` | Load test |
| `./lab coldstart` | First-request and later-request times |
| `./lab code` | An organizer's sign-in code (while email is off) |
| `./lab check [NAME]`, `./lab check --report` | Checks and the report |
| `./lab drift` | Differences between your Console changes and the code |
| `./lab pause` | Pause the job and deploys |
| `./lab down` | Delete everything the lab made |
