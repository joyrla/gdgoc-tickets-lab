# Pre-read: Cloud Ticketing lab

In this lab, reading the results matters more than running the commands. If you know these things going in, you'll know what you're looking at in each step.

Only read the material for the questions you can't answer.

| Basics | Check question | Reading |
|---|---|---|
| HTTP requests and responses | What do 200, 403, 404 and 500 each mean? | [MDN: An overview of HTTP](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Overview) |
| Containers | How are an image and a container different? | [Docker: What is a container?](https://docs.docker.com/get-started/docker-concepts/the-basics/what-is-a-container/) |
| How Cloud Run is organized | What are a service, a revision, an instance and a job? | [Cloud Run resource model](https://docs.cloud.google.com/run/docs/resource-model) |
| Autoscaling and concurrency | If one instance handles 40 requests at once, how many instances do 200 concurrent requests need at minimum? | [Instance autoscaling](https://docs.cloud.google.com/run/docs/about-instance-autoscaling), [Concurrency](https://docs.cloud.google.com/run/docs/about-concurrency) |
| Pub/Sub | How are a topic and a subscription different? How are push and pull subscriptions different? | [Pub/Sub overview](https://docs.cloud.google.com/pubsub/docs/overview), [Subscription types](https://docs.cloud.google.com/pubsub/docs/subscription-overview) |
| Eventarc | When an event happens, who delivers it, and where to? | [Eventarc overview](https://docs.cloud.google.com/eventarc/docs/overview) |
| Service accounts | How is a service account different from a person's account? | [Service accounts overview](https://docs.cloud.google.com/iam/docs/service-account-overview) |
| Transactions | Why is it a problem if two people sign up for the last seat at the same moment? | [Firestore transactions](https://docs.cloud.google.com/firestore/docs/manage-data/transactions) |

## Terms to know before the lab

| Term | Meaning |
|---|---|
| Cold start | No instance is running, so a request waits for a new one to start |
| Pre-warming | Raising the minimum instance count before a rush |
| Idempotency | Running the same operation many times has the same result as running it once |
| Dead letter | Where messages go after all retries have failed |
| Rollback | Moving traffic back to an earlier version when something goes wrong |

## Prepare

- Check your Google Cloud free trial's remaining days and credit
- Check that you can sign in to your personal GitHub account

Setup is one command. The code that creates the infrastructure (Terraform) isn't part of this lab, and has its own session.
