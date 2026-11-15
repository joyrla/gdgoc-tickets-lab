# 사전 학습: Cloud Ticketing 실습

실습에서는 명령을 실행하는 것보다 결과를 읽는 일이 더 중요합니다. 아래 내용을 알고 시작하면 각 단계에서 무엇을 보고 있는지 알 수 있습니다.

확인 질문에 답하기 어려운 항목만 자료를 읽으면 됩니다.

| 기초 | 확인 질문 | 자료 |
|---|---|---|
| HTTP 요청과 응답 | 200, 403, 404, 500 응답은 각각 무슨 뜻인가요? | [MDN: HTTP 개요](https://developer.mozilla.org/ko/docs/Web/HTTP/Guides/Overview) |
| 컨테이너 | 이미지와 컨테이너는 어떻게 다른가요? | [Docker: What is a container?](https://docs.docker.com/get-started/docker-concepts/the-basics/what-is-a-container/) |
| Cloud Run의 구성 | 서비스, 리비전, 인스턴스, 잡은 각각 무엇인가요? | [Cloud Run 리소스 모델](https://docs.cloud.google.com/run/docs/resource-model?hl=ko) |
| 자동 확장과 동시성 | 인스턴스 하나가 동시에 처리하는 요청 수가 40이면, 동시 요청이 200개일 때 인스턴스는 최소 몇 개 필요한가요? | [인스턴스 자동 확장](https://docs.cloud.google.com/run/docs/about-instance-autoscaling?hl=ko), [동시성](https://docs.cloud.google.com/run/docs/about-concurrency?hl=ko) |
| Pub/Sub | 토픽과 구독의 차이는 무엇인가요? push와 pull 구독은 어떻게 다른가요? | [Pub/Sub 개요](https://docs.cloud.google.com/pubsub/docs/overview?hl=ko), [구독 유형](https://docs.cloud.google.com/pubsub/docs/subscription-overview?hl=ko) |
| Eventarc | 이벤트가 생기면 누가 어디로 전달하나요? | [Eventarc 개요](https://docs.cloud.google.com/eventarc/docs/overview?hl=ko) |
| 서비스 계정 | 사람 계정과 서비스 계정은 어떻게 다른가요? | [서비스 계정 개요](https://docs.cloud.google.com/iam/docs/service-account-overview?hl=ko) |
| 트랜잭션 | 두 사람이 마지막 자리를 동시에 신청하면 왜 문제가 되나요? | [Firestore 트랜잭션](https://docs.cloud.google.com/firestore/docs/manage-data/transactions?hl=ko) |

## 실습 전에 알아 둘 용어

| 용어 | 뜻 |
|---|---|
| 콜드 스타트 | 실행 중인 인스턴스가 없어, 요청이 새 인스턴스가 시작되기를 기다리는 것 |
| 사전 준비(pre-warm) | 요청이 몰리기 전에 최소 인스턴스 수를 올려 두는 것 |
| 멱등성 | 같은 작업을 여러 번 실행해도 결과가 한 번 실행한 것과 같은 성질 |
| dead letter | 재시도에 모두 실패한 메시지를 따로 모아 두는 곳 |
| 롤백 | 문제가 생겼을 때 트래픽을 이전 버전으로 되돌리는 것 |

## 준비

- Google Cloud 무료 체험 계정의 남은 기간과 크레딧 확인
- 개인 GitHub 계정의 로그인 확인

설치는 명령 하나로 끝납니다. 인프라를 만드는 코드(Terraform)는 이번 실습의 범위가 아니며, 별도 회차에서 다룹니다.
