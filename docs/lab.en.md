# Cloud Ticketing lab

You put a finished event-signup service into your own Google Cloud project with one command. Then you sign up, cancel and rush it for real, and follow in the Console where each request goes through the cloud. A few things you break on purpose and fix. You write no code.

| | |
|---|---|
| Level | Introductory (200) |
| Time | 70-minute session + about 3 hours over two weeks (in four sittings) |
| Cost | Taken from the free trial credit. A 12,000 won budget alert is set. Real cost is a few thousand won |
| Last checked | 2026-11-16 (updated after the full test run) |

**By the end you can**

- Follow one signup through `web` → Pub/Sub → worker → Firestore to a ticket, in the Console and the logs
- Explain which problem a queue, an event and a scheduled job each solve
- Read a 403, a retry, a dead letter and a failed revision, and find the one setting behind each
- Compare autoscaling, concurrency, cold start and pre-warm with your own measurements
- Deploy from GitHub without keys, and explain why a broken version never reaches users
- Keep a third-party key in Secret Manager and explain who can read it

## How to read this

- ☰ is the navigation menu at the top left of the Console. "☰ → **Cloud Run → Services**" means: in ☰, point at **Cloud Run** and click **Services**.
- **Pub/Sub, Eventarc, Cloud Scheduler and Logging are not in the default ☰ list.** Once, open ☰ → **View all products** and click the ☆ on those four rows; they then appear under **Favorite products** at the top of ☰.
- Bold text is a Console button or field. If your Console is in Korean, use the Korean sheet (`lab.ko.md`).
- On every screen, first check that the project menu at the top shows your lab project.
- Names with underscores, like `PROJECT_ID`, are your own values.

**Each mission:** predict → do → where to look → check → why. Write the prediction in one line before you start. Wrong predictions are fine; they are the ones you remember.

**Submission cues:** **Submit 1** to **Submit 6** are required screenshots; **Optional** ones are up to you. They are collected in [Submission](#submission) at the end.

**When stuck:** after 20 minutes, post the mission number, the `./lab check` output and the error screen in the help thread. If something is broken, running `./lab up PROJECT_ID` again puts every setting back to the code's version.

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
| IAM role a service assumes | Service account |
| Resource policy (`lambda:InvokeFunction`) | A role granted on the resource (`Cloud Run Invoker`) |
| CloudFormation stack | Nothing in the Console; the Terraform code and state play that role |

## What gets built

![Architecture](architecture.png)

| Part | What it does |
|---|---|
| `web` (Cloud Run service, public) | Event pages and API. Saves the seat in Firestore, leaves a "make a ticket" message, and answers at once |
| Pub/Sub topic `registrations` and subscription `ticket-worker` | Holds messages and delivers them to the worker. Retries on failure; after 5 failures, moves the message to `dead-letter` |
| `ticket-worker` (service, internal only) | Makes the QR ticket and sends email |
| Eventarc trigger and `waitlist-promoter` (service, internal only) | When a registration changes (a cancel), gives the seat to the first person waiting |
| Cloud Scheduler and `housekeeping` (Cloud Run job) | Every 5 minutes: deadlines, resending stuck tickets, filling free seats, pre-warming before an opening |
| Firestore | Events, registrations, seat counters |
| 8 service accounts | One per part, with only the permissions it needs |

## Schedule

| Sitting | Missions | Time |
|---|---|---|
| 1 (session) | 0 Setup, 1 Look around | 70 min |
| 2 | 2 Follow one signup, 3 Connect the queue to the worker, 4 Worker failure and dead letter | 60 min |
| 3 | 5 Cancel and events, 6 Revisions and rollback, 7 Cold start and pre-warm | 60 min |
| 4 | 8 The rush, 9 Deploy from GitHub | 60 min |
| 5 | 10 Real email and secrets, 11 Cost and pause, submission | 40 min |

---

# Sitting 1. Setup and a look around

## Mission 0. Project, budget, build it all (15 min + 25 min waiting)

**Do.**
1. ☰ → **IAM & Admin → Create a project**. Enter a name and note the **Project ID** under it. **Create**.
2. Select the new project in the project menu at the top.
3. ☰ → **Billing**. If it says no billing account is linked, use **Link a billing account** to link your free trial account.
4. ☰ → **Billing** → left menu **Budgets & caps** → **Create new**.
   - **Definition**: **Alerts only**. Any name. **Next**
   - **Scope**: under **Projects**, tick only your lab project. **Next**
   - **Amount**: target amount `12000`. **Next**
   - **Actions**: defaults (50%, 90%, 100%) → **Finish**
5. Click **Activate Cloud Shell** (>_) at the top right. Sign in to GitHub and get the lab repository. You must accept the GitHub invitation from your instructor first.

   ```bash
   gh auth login --web --scopes workflow
   gh repo clone joyrla/gdgoc-tickets-lab
   cd gdgoc-tickets-lab
   ./lab up PROJECT_ID
   ```

   At `gh auth login`, press Enter and type the code on screen at [github.com/login/device](https://github.com/login/device).

What `./lab up` does: installs tools, turns on APIs, builds four images, then uses Terraform to create 3 services, a job, the topics and subscriptions, an Eventarc trigger, the schedule, 8 service accounts, 4 secrets and about 30 permissions. It takes 20 to 25 minutes. Do Mission 1 while you wait.

**Check.** The last line shows your site's address. Opening it shows an empty event list.

**Why.** A budget only sends alerts; it does not stop anything. **Do not click "Upgrade to a full account".** Building these parts by hand in the Console takes 6 to 8 hours, most of it filling in forms. This lab spends that time using, breaking and measuring what was built. Building it is the topic of the next session (Terraform).

**Stuck?**

| Message | Fix |
|---|---|
| `cannot see project` | A typo in the project ID. It differs from the project name |
| `no billing account linked` | Step 3 |
| The repository won't clone | Check that you accepted the GitHub invitation |
| `Google Cloud is not ready yet` | Common in a new project. The command retries by itself a minute later |
| Cloud Shell disconnected | Reopen it and run `cd ~/gdgoc-tickets-lab && ./lab up PROJECT_ID` |

## Mission 1. Look around (15 min, while `./lab up` runs)

Look at what is being built. Parts appear in the Console as `./lab up` finishes them.

**Do.** Find the answers to these five questions in the Console and write them down.

1. ☰ → **Cloud Run → Services** → `web` → **Security** tab: which service account does `web` run as?
2. `web` → **Containers** tab, variables: which topic will signup messages go to? (Hint: compare with the topic names in Pub/Sub)
3. ☰ → **Pub/Sub → Subscriptions** → `ticket-worker` → **Details**: what is the delivery type, and where does a message go after how many failures?
4. ☰ → **Cloud Run → Services** → tick `ticket-worker` → **Permissions**: who may call `ticket-worker`? Which subscription uses that account right now? (Hint: the `mailer` subscription in Pub/Sub)
5. ☰ → **Eventarc → Triggers** → `registration-changed`: which changes does it react to?

`./lab iam` shows every account's permissions and the reason for each in one table.

**Why.** The Console shows what exists now, one part at a time. How the parts connect only shows when you follow it, as in these five questions. The code (`infra/*.tf`) holds what should exist and why.

---

# Sitting 2. Follow one signup

## Mission 2. Follow one signup (15 min)

**Do.**
1. Create an event in Cloud Shell.

   ```bash
   ./lab event wiring
   ```

2. Open the address in the output (`/events/wiring`) and sign up with your own email.
3. Click **View ticket**.

**Predict.** Will the ticket page show a QR code?

**Where to look.**
- ☰ → **Firestore** → `(default)` → **Firestore Studio** → `registrations`: your new document and its `status`
- ☰ → **Pub/Sub → Subscriptions** → `ticket-worker` → **Messages** tab → **Pull**. Leave **Enable ack messages** unticked. Pull only once (each pull counts as a delivery attempt).

**Check.** The ticket stays at **Issuing your ticket**. One `{"registration_id": ...}` message is waiting in the subscription.

**Why.** `web` saved the seat in Firestore, left a message and answered right away. The subscription is **Pull** for now, so it just keeps the message until someone takes it. Nothing is lost. Because signup and ticketing are split, signups keep working even when ticketing is slow or stopped.

> **Optional:** the waiting message and the "issuing" ticket page

## Mission 3. Connect the queue to the worker (15 min, by hand)

This is the connection you build yourself in this lab.

**Do.**
1. ☰ → **Cloud Run → Services** → copy the **URL** of `ticket-worker`.
2. ☰ → **Pub/Sub → Subscriptions** → `ticket-worker` → **Edit**.
3. **Delivery type**: **Push**. **Endpoint URL**: the URL you copied. Leave **Enable authentication** **unticked** → **Update**.

**Predict.** Will the ticket appear now?

**Where to look.** ☰ → **Cloud Run** → `ticket-worker` → **Observability** tab, logs.

**Check.** `403` and `The request was not authenticated` repeat. When you see it 2 or 3 times, take a screenshot of the log (**Submit 1**) and fix it right away. After 5 failures the message moves to `dead-letter`.
1. Subscription → **Edit** → tick **Enable authentication** → **Service account** `tickets-pubsub-push` → **Update**.
2. Within a minute or two, the ticket from Mission 2 is issued. Do not sign up again.

`./lab check push`

**Why.** `ticket-worker`'s ingress is **Internal**, so requests from Pub/Sub may come in (from the internet they get 404). But it requires authentication, so an unsigned request gets 403. With authentication on, Pub/Sub signs as `tickets-pubsub-push`, which holds **Cloud Run Invoker** on `ticket-worker`. Getting through the door (ingress) and being allowed in (IAM) are separate.

> **Submit 1 screenshot:** the `403` log (before the fix), the issued ticket (after)

**Stuck?** If the ticket stays "issuing" after the fix, the message already moved to `dead-letter`. Send it back with the replay in Mission 4.

## Mission 4. Worker failure and dead letter (20 min)

**Problem.** If the worker breaks, what happens to the people signing up?

**Do.**
1. ☰ → **Cloud Run** → `ticket-worker` → **Containers** tab → **Variables & Secrets** → **Add variable**: `WORKER_FAIL_RATE` = `1`.
2. Top right **Review changes and redeploy** → check the changed line → **Deploy changes**.
3. In a browser **private window**, open `/events/wiring` and sign up with another email.

**Predict.** Will the signup succeed? What happens to the ticket?

**Where to look.**
- `ticket-worker` logs: `simulated failure` and `500`
- Subscription `ticket-worker` → **Dead lettering** tab: where failed messages go
- 2 to 3 minutes later, subscription `dead-letter` → **Messages** → **Pull** (**Enable ack messages** unticked)

**Check.** The signup succeeds. `500` repeats a few times and stops, and the message is in `dead-letter`. Take both screenshots before fixing (**Submit 2**).

Now fix it.
1. In the **Containers** tab, delete `WORKER_FAIL_RATE` → **Review changes and redeploy** → **Deploy changes**.
2. Wait a minute, then send the failed message back (a message you pulled stays hidden for one minute).

   ```bash
   scripts/replay-dead-letters.sh --replay
   ```

3. The ticket is issued within seconds. A few minutes later, look for `skip ... (status issued)` in the logs.

**Why.** Because signup and ticketing are split by a message, signups keep working while the worker is broken. Retries fix short failures; a failure that retries cannot fix stays in `dead-letter` after 5 tries for a person to look at. The `skip` line is the job, which runs every 5 minutes, sending the stuck ticket once more. Even when the same message arrives twice, the worker first checks "did I already issue this?", so there is still one ticket (idempotency).

> **Submit 2 screenshot:** the repeated `500` logs and the message waiting in `dead-letter` (both before the fix)

---

# Sitting 3. Events, revisions, cold start

## Mission 5. Cancel and events (10 min)

**Problem.** When someone cancels, the first person waiting should get the seat. Cancels happen in many places: the attendee, an organizer, the deadline job.

**Do.**
1. Create an event with 1 seat and a waitlist of 1.

   ```bash
   ./lab event promo --seats 1 --waitlist 1
   ```

2. Sign up for `/events/promo` in a normal window. Sign up again with another email in a private window; that one is **waitlist #1**.
3. On the first ticket page, click **Cancel registration**.

**Predict.** Who gives the seat to the waiting person, and what triggers it?

**Where to look.** The private window's ticket page, `waitlist-promoter` logs, and the `status` of both documents in Firestore Studio → `registrations`.

**Check.** The waiting person gets a ticket within seconds.

**Why.** The cancel changes a Firestore document; Eventarc delivers that change to `waitlist-promoter`. `web` knows nothing about the waitlist. Because the system reacts to the data change itself, a cancel from anywhere is handled in one place. If delivery fails, the job that runs every 5 minutes fills free seats anyway: events for speed, a periodic sweep for correctness.

> **Optional:** the waiting person's issued ticket and the `waitlist-promoter` log

## Mission 6. Revisions and rollback (15 min)

**Do.**
1. ☰ → **Cloud Run** → `web` → **Containers** tab → **Add variable**: `LAB_NOTE` = `v2`.
2. **Review changes and redeploy** → **untick** **Serve this revision immediately** at the bottom → **Deploy changes**.
3. `web` → **Revisions** tab.

**Predict.** How many users see the new revision?

**Check.** There is a new revision with 0% of traffic.

4. **Revisions** → **Manage traffic**: new revision 50%, previous revision 50% → **Save**.
5. See which revision answers, ten times.

   ```bash
   URL=$(gcloud run services describe web --region asia-northeast3 --format='value(status.url)')
   for i in $(seq 10); do curl -sI "$URL/health" | grep -i x-served-by; done
   ```

   Both revision names appear. Take the screenshot (**Submit 3**).
6. Roll back: in **Manage traffic**, set the previous revision to 100% → **Save**. Now only one name appears.
7. Finally, set the latest revision back to 100%.

**Why.** Every deploy creates a new revision, and how much traffic it gets is a separate decision. A rollback just moves traffic back to a revision that already exists, with no build, so it takes seconds. The automatic deploy in Mission 9 uses the same idea to keep broken versions away from users.

> **Submit 3 screenshot:** the **Revisions** tab split 50/50 and the `curl` output

## Mission 7. Cold start and pre-warm (25 min, including waiting)

**Cold start.** Do this first in the sitting, when the site has not been opened for more than 15 minutes.

```bash
./lab coldstart
```

**Predict.** How different are the first request and the ones after it?

**Check.** The first request takes seconds; the next ones under 0.1 s. Write both in the measurement table.

**Pre-warm.**
1. Create an event whose signups open in 20 minutes.

   ```bash
   ./lab event opening --opens-in 20
   ```

2. ☰ → **Cloud Scheduler** → tick the `housekeeping` row → **Force run**, so the job runs now instead of in up to 5 minutes.
3. ☰ → **Cloud Run → Jobs** → `housekeeping` → **History** tab → the run you just started → logs.

**Predict.** What will the job do to `web`?

**Check.** The log says `pre-warm: web minimum instances 0 → 3`. In `web` → **Observability**, the instance count graph shows 3 instances. An hour after the opening, the job sets it back to 0.

**Why.** With 0 instances, the first request waits for a container to start. Scaling to zero means no cost at night; the price is a slow first request. When the opening time is known, the job starts instances in advance. The wait disappears, but you pay while no requests come in. The job may change `web`'s setting only because of a custom role with exactly two permissions (read and update) (`./lab iam`, `housekeeping`).

> **Submit 4 screenshot:** the `./lab coldstart` output and the graph with 3 instances up before the opening

---

# Sitting 4. The rush and deploys

## Mission 8. The rush (25 min)

**Do.**
1. Create an event that opens in 3 minutes (100 seats, waitlist 50) and start the load test right away. 300 visitors wait before the opening and sign up the moment it opens.

   ```bash
   ./lab event rush-a --opens-in 3 --seats 100 --waitlist 50
   ./lab load rush-a
   ```

**Predict.** How many instances will there be at most? Will more than 100 tickets be issued?

**Where to look.** (graphs appear 3 to 5 minutes late)
- `web` → **Observability**: instance count, request latency
- Subscription `ticket-worker` → **Metrics**: unacked messages
- Firestore Studio → `event_counts` → `rush-a`: `held` (registrations holding a seat) and `issued` (tickets issued)

**Check.** Locust's `Signups:` line and response-time table, and `held` = `issued` = 100. Write them in the measurement table and take the screenshots (**Submit 5**). Because the event opens within minutes, pre-warm (Mission 7) may have started 3 instances first; look at how many more the graph shows above those 3.

2. Measure again with another concurrency. `web` → **Containers** tab → **Maximum concurrent requests per instance** `2` → **Review changes and redeploy** → **Deploy changes**.

   ```bash
   ./lab event rush-c --opens-in 1 --seats 100 --waitlist 50
   ./lab load rush-c --users 150 --minutes 3
   ```

3. When it ends, set concurrency back to `40`.

**Predict.** With half the visitors, will there be more instances than the first time, or fewer?

**Why.** Cloud Run adds instances by looking at concurrent requests per instance. With lower concurrency, the same load needs more instances. Every signup changes the event's single seat-counter document in a transaction, so seats are exact, but signups per second have a ceiling. More instances do not move that ceiling.

> **Submit 5 screenshot:** `web`'s instance count graph and the Locust result (`Signups:` line and response-time table)

## Mission 9. Deploy from GitHub (30 min)

**Do.**
1. Create your GitHub copy and the keyless sign-in.

   ```bash
   ./lab github
   cd ~/gdgoc-tickets
   ```

   The last line of the output is `Sign-in test passed`.
2. In your copy: **Settings → Secrets and variables → Actions → Variables** → **New repository variable**: `DEPLOY_ENABLED` = `true`.
3. Add code that fails only on Cloud Run. Open it with `cloudshell edit web/events.py` and add two lines at the top of the `home` function.

   ```python
       if get_settings().on_cloud_run:  # only on Cloud Run, so the tests still pass
           raise RuntimeError("deliberate failure")
   ```

   ```bash
   git add web && git commit -m "Break on Cloud Run" && git push
   ```

**Predict.** Will the site go down?

**Where to look.** Your copy's **Actions** → the new run → the steps of the `deploy` job, and `web`'s **Revisions** tab.

**Check.** The new revision starts at 0%, fails at **Smoke test web's new revision**, and **Put everything back** runs. The site keeps working.

4. Undo it and watch a good deploy.

   ```bash
   git revert --no-edit HEAD && git push
   ```

   The new revision passes its checks at 0%, then gets 100%. Its image tag is the commit SHA.
5. Test the keyless sign-in rule: try to sign in from a branch that is not `main`.

   ```bash
   git switch -c try-branch && git push -u origin try-branch
   ```

   **Actions** → left **Sign-in test** → **Run workflow** → Branch `try-branch` → **Run workflow**. Take a screenshot of the failure (**Submit 6**). Then `git switch main && git push origin --delete try-branch`.

**Why.** For every run GitHub issues a short-lived token that contains the repository ID and the branch. Google Cloud accepts only tokens that match the rule (your repository ID, `main`) and exchanges them for `tickets-deployer`'s permissions. So no key is stored in GitHub, and other repositories or branches cannot deploy. A deploy puts the new revision at 0%, checks it, and only then sends traffic; if the check fails, traffic stays on the previous revision.

> **Submit 6 screenshot:** the failed Sign-in test on `try-branch` (`rejected by the attribute condition` or similar)

---

# Sitting 5. Email, cost, wrap-up

## Mission 10. Real email and secrets (20 min)

Until now email was off, and every email the app would send was a "not sent" log line. Use the **mail key** and the **sender address** your instructor sent you in a private message. Treat the key like a password: never put it in chat, code or a screenshot.

**Do.**
1. ☰ → **Security → Secret Manager** → `smtp-password` → **Versions** tab → **New version** → paste the mail key as the value → add it.
2. `mail-from` → **New version** → the sender address → add it.
3. Turn email on.

   ```bash
   ./lab mail on
   ```

4. At `/login`, request a code for your own email. The code now arrives in your inbox instead of the logs.
5. Sign up for `/events/wiring` once more with your own email. A signup email and a ticket email arrive.

**Predict.** Can `web` read the mail key?

**Where to look.** `smtp-password` → **Permissions** tab. Where the secrets are attached in the **Containers** tab of `ticket-worker` and of `web`.

**Check.** Only `tickets-ticket-worker` can read the key. `./lab check mail`.

**Why.** A third-party key goes in Secret Manager, not in code or a plain variable. To change the key you add a new version, and the service reads it when it starts. The permission is on this one secret and for the one worker that sends mail, so even if `web` were compromised, the mail key would not leak. The load test's `@example.com` addresses are a domain reserved for tests, so no email goes to them even with mail on.

> **Optional:** the code email in your inbox (hide the code) and the **Permissions** tab of `smtp-password`

## Mission 11. Cost and pause (15 min)

**Do.**
1. ☰ → **Billing → Reports**. Filter by your project and group by service. Costs appear about a day late.
2. See how your Console changes differ from the code.

   ```bash
   ./lab drift
   ```

3. Pause the lab.

   ```bash
   ./lab pause
   ./lab check --report
   ```

**Why.** With no requests, the services scale to zero and cost nothing. The job runs every 5 minutes, 288 times a day, so it is paused. The differences `./lab drift` shows are where the next session (Terraform) starts: changes made in the Console are not in the code, and re-applying the code (`./lab up`) removes them. Do not delete the project.

> **Optional:** the billing report (filtered by project, grouped by service)

---

# Submission

Upload to the announced survey. **Required** items are graded; **optional** ones are not.

## Required 1. Six core concepts

One screenshot and one question per concept. Three to five sentences per answer is enough.

**Scoring:** 3 points per concept. Screenshot 1 point, answer 2 points (1 for a correct answer, 2 if the reason is backed by your own screenshot or measurements).

**1. Service accounts and IAM (Mission 3)**
- Screenshot: **Submit 1**. The `403` in the `ticket-worker` log (before), the issued ticket (after)
- Question: Which setting let the request in, and which one refused it with 403? Which account's which role let it through?

**2. Pub/Sub and asynchronous work (Mission 4)**
- Screenshot: **Submit 2**. The repeated `500` logs and the message waiting in `dead-letter`
- Question: While the worker failed, what did the person signing up experience, and what did they not? Where did the message end up, and why there?

**3. Revisions and safe deploys (Mission 6)**
- Screenshot: **Submit 3**. The **Revisions** tab split 50/50 and the `curl` output
- Question: Who sees a revision with 0% traffic? Why does a rollback take seconds?

**4. Cold start, pre-warm, cost (Mission 7)**
- Screenshot: **Submit 4**. The `./lab coldstart` output and the graph with 3 instances before the opening
- Question: Why was the first request slow? How does pre-warm prevent it, and what does it cost? Name one case where pre-warm is not needed.

**5. Autoscaling and concurrency (Mission 8)**
- Screenshot: **Submit 5**. The instance count graph and the Locust result
- Question: How many instances did you get, and why? What changed at concurrency 2? Why did signups per second stop rising even with more instances?

**6. Keyless deploy (Mission 9)**
- Screenshot: **Submit 6**. The failed Sign-in test on `try-branch`
- Question: What stops someone else's repository, or another branch, from deploying to your project? Why don't you need to store a key in GitHub?

## Required 2. Also hand in

1. `~/lab-report.txt` (from `./lab check --report` in Mission 11)
2. The measurement table

   | | Concurrency 40 (`rush-a`) | Concurrency 2 (`rush-c`) |
   |---|---|---|
   | Max `web` instances | | |
   | Signup response median (50%) | | |
   | Signup response 95% | | |
   | Peak signups per second | | |

   Cold start first request / later requests: ____ / ____.

3. One design question: **If ten times as many people signed up at the opening, what would hit its limit first, and what would you change?** Base your answer on your measurements.
4. The feedback survey (confidence 1 to 5 per concept, the most confusing mission)

## Optional

| Mission | Concept | Question |
|---|---|---|
| 1 | Architecture | Your answers to the five questions. Which connection was hard to see in the Console? |
| 2 | Pull subscription | The signup answered, so why was there no ticket? Where was the message? |
| 4 | Idempotency | Why is there still one ticket when the same message arrives twice? |
| 5 | Eventarc | Who gave the seat to the waiting person, and what started it? |
| 7 | Jobs and Cloud Scheduler | Why is `housekeeping` a job and not a service? |
| 10 | Secret Manager | Which account can read the mail key? What would you do if the key leaked? |
| 11 | Drift | Where did the differences in `./lab drift` come from? |

# Advanced (optional, goals only)

- Make a full event answer "full" without a transaction, and measure Mission 8 again
- Split the seat counter into several documents and measure again
- Add one alert that would have caught Mission 4's failure
- Find Mission 3's subscription change in the Terraform code (`infra/events.tf`) and write down how to make it in code instead of the Console

# Shortcut commands

| Command | What it does |
|---|---|
| `./lab up PROJECT_ID` | Build everything. Run it again to reset to the code's settings |
| `./lab iam` | Every account's permissions and why |
| `./lab event ID [--opens-in MINUTES] [--seats N] [--waitlist N]` | Create a published event |
| `./lab load EVENT_ID [--users N] [--minutes M]` | Load test |
| `./lab coldstart` | First request vs later requests |
| `./lab github` | Your GitHub copy and keyless sign-in |
| `./lab mail on`, `./lab mail off` | Turn real email on or off |
| `./lab code` | The organizer sign-in code (while email is off) |
| `./lab check [NAME]`, `./lab check --report` | Checks and the report |
| `./lab drift` | Differences between your Console changes and the code |
| `./lab pause` | Pause the job and deploys |
| `./lab down` | Delete everything the lab made |
