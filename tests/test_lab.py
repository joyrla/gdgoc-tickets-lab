"""The lab script (./lab) against a pretend Google Cloud.

The checks decide whether a student's hand-built step passes, so each one is tried with the
right settings and with the mistakes students make: the wrong identity, a missing grant, an
unsigned push. The shortcuts must never make twice what a student already made by hand.
"""

import importlib.machinery
import importlib.util
import json
import os
import re
import subprocess
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parent.parent


def load_lab(home):
    os.environ["LAB_HOME"] = str(home)  # never the real ~/.gdgoc-lab
    loader = importlib.machinery.SourceFileLoader("lab", str(REPO / "lab"))
    spec = importlib.util.spec_from_loader("lab", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    del os.environ["LAB_HOME"]
    assert module.TFVARS == home / "terraform.tfvars"
    return module


@pytest.fixture
def lab(tmp_path, monkeypatch):
    module = load_lab(tmp_path / "home")
    monkeypatch.setattr(module, "gh", lambda *args: None)
    return module


P = "student-1"
N = "123456789012"


def sa(key):
    return f"tickets-{key}@{P}.iam.gserviceaccount.com"


def make_cloud(lab, gcloud=None, api=None, policies=None):
    """A cloud whose answers come from dicts: gcloud by its arguments, the Cloud Run API by path."""
    gcloud, api, policies = gcloud or {}, api or {}, policies or {}

    class Fake(lab.Cloud):
        def gcloud(self, *args, project=True):
            return gcloud.get(" ".join(args))

        def run_api(self, path):
            return api.get(path)

        def policy(self, kind, name):
            return policies.get((kind, name), {})

    cloud = Fake(P, "asia-northeast3", "student@example.com")
    cloud._number = N
    return cloud


def bindings(*pairs):
    return {"bindings": [{"role": role, "members": [member]} for role, member in pairs]}


def good_web(lab):
    cloud = make_cloud(lab)
    env = [{"name": k, "value": v} for k, v in lab.env_web(cloud).items()]
    env += [
        {
            "name": "TICKET_SECRET",
            "valueSource": {"secretKeyRef": {"secret": f"projects/{P}/secrets/ticket-secret", "version": "1"}},
        },
        {"name": "SESSION_SECRET", "valueSource": {"secretKeyRef": {"secret": "session-secret", "version": "1"}}},
    ]
    return {
        "terminalCondition": {"state": "CONDITION_SUCCEEDED"},
        "ingress": "INGRESS_TRAFFIC_ALL",
        "invokerIamDisabled": True,
        "scaling": {"maxInstanceCount": 20},
        "uri": "http://127.0.0.1:9",  # nothing answers: the site check fails on its own line
        "template": {
            "serviceAccount": sa("web"),
            "maxInstanceRequestConcurrency": 40,
            "containers": [{"image": "x/web:lab", "env": env, "startupProbe": {"httpGet": {"path": "/health"}}}],
        },
    }


def web_policies():
    reader = "roles/secretmanager.secretAccessor"
    return {
        ("secret", "ticket-secret"): bindings((reader, f"serviceAccount:{sa('web')}")),
        ("secret", "session-secret"): bindings((reader, f"serviceAccount:{sa('web')}")),
    }


def run(lab, check, cloud):
    result = lab.Result()
    check(cloud, result)
    return result


def problems(result):
    return [text for kind, text in result.lines if kind == "NOT"]


# ---------- settings


def test_settings_round_trip_and_parts_keep_the_order_of_lab_tf(lab):
    values = {"project_id": P, "github_repo_id": "0", "admin_emails": ["a@example.com"], "lab_parts": ["start"]}
    lab.write_tfvars(values)
    assert lab.read_tfvars() == values
    assert lab.add_parts(values, ["workers", "base"]) == ["start", "base", "workers"]


def test_lab_parts_names_match_terraform():
    lab_tf = (REPO / "infra/lab.tf").read_text()
    names = re.search(r"lab_part_names = \[(.*?)\]", lab_tf).group(1)
    assert [n.strip(' "') for n in names.split(",")] == load_lab(Path("/nonexistent/home")).PARTS


def test_a_real_tfvars_file_is_left_alone(lab, tmp_path, monkeypatch):
    infra = tmp_path / "infra"
    infra.mkdir()
    (infra / "terraform.tfvars").write_text('project_id = "production"\n')
    monkeypatch.setattr(lab, "INFRA", infra)
    with pytest.raises(SystemExit):
        lab.link_settings()
    assert (infra / "terraform.tfvars").read_text() == 'project_id = "production"\n'


def test_settings_are_linked_into_any_clone(lab, tmp_path, monkeypatch):
    infra = tmp_path / "infra"
    infra.mkdir()
    monkeypatch.setattr(lab, "INFRA", infra)
    lab.link_settings()
    assert (infra / "terraform.tfvars").readlink() == lab.HOME / "terraform.tfvars"


def test_the_pasted_settings_match_terraform(lab):
    """A web or job built by hand gets the same settings as one Terraform builds."""
    run_tf = (REPO / "infra/run.tf").read_text()
    common = re.search(r"common_env = \{(.*?)\n  \}", run_tf, re.S).group(1)
    names = set(re.findall(r"^\s+([A-Z_]+)\s+=", common, re.M)) - {"STAFF_EMAILS"}  # empty in the lab
    cloud = make_cloud(lab)
    assert names <= set(lab.env_web(cloud)) and names <= set(lab.env_job(cloud))
    job_names = set(re.findall(r"^\s+(WEB_SERVICE|WEB_MIN_INSTANCES|PREWARM_\w+)\s+=", run_tf, re.M))
    assert job_names == set(lab.env_job(cloud)) - set(lab.common_env(cloud))


def test_every_role_in_the_permission_table_is_one_terraform_grants(lab):
    terraform = "".join(p.read_text() for p in (REPO / "infra").glob("*.tf"))
    for _, _, _, role, _, _ in lab.DESIGN:
        assert role.split("/")[-1] in terraform, role


# ---------- checks


def test_web_built_as_the_sheet_says_passes_except_the_offline_site(lab):
    cloud = make_cloud(lab, api={"services/web": good_web(lab)}, policies=web_policies())
    assert [p for p in problems(run(lab, lab.check_web, cloud)) if "does not answer" not in p] == []


def test_web_on_the_default_identity_fails_and_says_where_to_fix_it(lab):
    web = good_web(lab)
    web["template"]["serviceAccount"] = f"{N}-compute@developer.gserviceaccount.com"
    cloud = make_cloud(lab, api={"services/web": web}, policies=web_policies())
    assert any("not tickets-web (Security tab)" in p for p in problems(run(lab, lab.check_web, cloud)))


def test_web_without_its_secret_grant_fails_on_that_secret(lab):
    policies = web_policies()
    del policies[("secret", "session-secret")]
    cloud = make_cloud(lab, api={"services/web": good_web(lab)}, policies=policies)
    found = problems(run(lab, lab.check_web, cloud))
    assert any("may not read session-secret" in p for p in found)
    assert not any("may not read ticket-secret" in p for p in found)


def test_a_missing_web_is_not_built_yet_rather_than_failed(lab):
    status, lines = lab.run_check(make_cloud(lab), 5)
    assert status == "-" and "no service web yet" in lines[0][1]


def worker_subscription(push):
    sub = {"topic": f"projects/{P}/topics/registrations", "ackDeadlineSeconds": 60}
    if push:
        sub["pushConfig"] = push
    return sub


def test_an_unsigned_push_fails_and_names_the_setting(lab):
    cloud = make_cloud(
        lab,
        gcloud={
            "pubsub subscriptions describe ticket-worker": worker_subscription(
                {"pushEndpoint": f"https://ticket-worker-{N}.asia-northeast3.run.app"}
            )
        },
        api={"services/ticket-worker": {"uri": f"https://ticket-worker-{N}.asia-northeast3.run.app"}},
    )
    assert problems(run(lab, lab.check_push, cloud)) == [
        "pushes are not signed as tickets-pubsub-push (Enable authentication)"
    ]


def test_a_signed_push_to_either_address_of_the_worker_passes(lab):
    push = {
        "pushEndpoint": "https://ticket-worker-abc123-du.a.run.app/",
        "oidcToken": {"serviceAccountEmail": sa("pubsub-push")},
    }
    cloud = make_cloud(
        lab,
        gcloud={"pubsub subscriptions describe ticket-worker": worker_subscription(push)},
        api={"services/ticket-worker": {"uri": "https://ticket-worker-abc123-du.a.run.app"}},
    )
    assert problems(run(lab, lab.check_push, cloud)) == []


def test_a_pull_subscription_has_not_reached_step_8(lab):
    cloud = make_cloud(lab, gcloud={"pubsub subscriptions describe ticket-worker": worker_subscription(None)})
    assert lab.run_check(cloud, 8)[0] == "-"


def test_the_scheduler_made_from_the_job_page_passes(lab):
    """The Console's Add scheduler trigger writes the older v1 address; both start the same job."""
    job = {
        "template": {
            "template": {
                "serviceAccount": sa("housekeeping"),
                "maxRetries": 0,
                "timeout": "240s",
                "containers": [
                    {"env": [{"name": "WEB_SERVICE", "value": f"projects/{P}/locations/asia-northeast3/services/web"}]}
                ],
            }
        }
    }
    scheduler = {
        "name": f"projects/{P}/locations/asia-northeast3/jobs/housekeeping",
        "schedule": "*/5 * * * *",
        "timeZone": "Asia/Seoul",
        "state": "ENABLED",
        "httpTarget": {
            "uri": f"https://asia-northeast3-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/{P}/jobs/housekeeping:run",
            "oauthToken": {"serviceAccountEmail": sa("scheduler")},
        },
    }
    cloud = make_cloud(
        lab,
        gcloud={"scheduler jobs list --location asia-northeast3": [scheduler]},
        api={"jobs/housekeeping": job},
        policies={("job", "housekeeping"): bindings(("roles/run.invoker", f"serviceAccount:{sa('scheduler')}"))},
    )
    assert problems(run(lab, lab.check_schedule, cloud)) == []
    assert lab.run_check(cloud, 26)[0] == "-"  # still running, so step 26 isn't done
    scheduler["state"] = "PAUSED"
    assert lab.run_check(cloud, 26)[0] == "ok"


def test_a_trust_open_to_every_repository_fails(lab, monkeypatch):
    monkeypatch.setattr(lab, "own_repo", lambda: "student/gdgoc-tickets")
    monkeypatch.setattr(lab, "gh", lambda *args: "555" if args[:2] == ("api", "repos/student/gdgoc-tickets") else None)
    pool = "principalSet://iam.googleapis.com/projects/123456789012/locations/global/workloadIdentityPools/github"
    cloud = make_cloud(
        lab,
        gcloud={
            "iam workload-identity-pools describe github --location global": {"state": "ACTIVE"},
            "iam workload-identity-pools providers describe gdgoc-tickets --workload-identity-pool github --location global": {
                "oidc": {"issuerUri": "https://token.actions.githubusercontent.com"},
                "attributeMapping": {
                    "attribute.repository_id": "assertion.repository_id",
                    "attribute.ref": "assertion.ref",
                },
                "attributeCondition": "assertion.repository_id == '555' && assertion.ref == 'refs/heads/main'",
            },
        },
        policies={
            ("sa", sa("deployer")): {
                "bindings": [
                    {
                        "role": "roles/iam.workloadIdentityUser",
                        "members": [f"{pool}/attribute.repository_id/555", f"{pool}/*"],
                    }
                ]
            }
        },
    )
    found = problems(run(lab, lab.check_trust, cloud))
    assert any(p.startswith(f"  also allowed: {pool}/*") for p in found)
    assert not any("may not act as tickets-deployer" in p for p in found)


def test_a_database_in_the_wrong_region_says_it_cannot_be_moved(lab):
    cloud = make_cloud(
        lab,
        gcloud={
            "firestore databases describe --database=(default)": {
                "type": "FIRESTORE_NATIVE",
                "locationId": "us-central1",
            }
        },
    )
    assert any("can't be changed" in p for p in problems(run(lab, lab.check_database, cloud)))


def test_skipped_steps_show_in_the_check(lab):
    lab.HOME.mkdir(parents=True)
    lab.record_skip(8)
    cloud = make_cloud(lab, gcloud={"pubsub subscriptions describe ticket-worker": worker_subscription(None)})
    assert lab.run_check(cloud, 8)[0] == "- (skipped)"


# ---------- shortcuts take over what a student already made


def test_takeover_imports_only_what_exists_and_is_not_in_terraform(lab, monkeypatch):
    calls = []

    def fake_terraform(*args, capture=True, env=None):
        calls.append(args)
        out = "google_pubsub_topic.registrations[0]\n" if args[0] == "state" else ""
        return subprocess.CompletedProcess(args, 0, out, "")

    monkeypatch.setattr(lab, "terraform", fake_terraform)
    existing = {"pubsub topics describe registrations": {}, "pubsub topics describe emails": {}}
    lab.adopt(make_cloud(lab, gcloud=existing), ["topics"], env={})
    imports = [c[3:] for c in calls if c[0] == "import"]
    assert imports == [("google_pubsub_topic.emails[0]", f"projects/{P}/topics/emails")]


def test_a_shortcut_keeps_a_push_the_student_made_on_a_terraform_subscription(lab, monkeypatch):
    lab.write_tfvars(
        {
            "project_id": P,
            "github_repo_id": "0",
            "admin_emails": ["a@example.com"],
            "lab_parts": ["start", "base", "topics"],
        }
    )
    monkeypatch.setattr(lab, "terraform_env", lambda: {})
    monkeypatch.setattr(lab, "ensure_terraform", lambda env: None)
    monkeypatch.setattr(lab, "adopt", lambda cloud, parts, env: None)
    monkeypatch.setattr(lab, "terraform", lambda *a, **k: subprocess.CompletedProcess(a, 0, "", ""))
    pushed = {"pubsub subscriptions describe ticket-worker": {"pushConfig": {"pushEndpoint": "https://ticket-worker"}}}
    lab.apply(make_cloud(lab, gcloud=pushed), ["workers"])
    assert lab.read_tfvars()["lab_parts"] == ["start", "base", "topics", "workers", "push"]


def test_every_skip_names_parts_terraform_knows(lab):
    for step, parts in lab.SKIPS.items():
        assert set(parts) <= set(lab.PARTS), step
    for name, (parts, _) in lab.SHORTCUTS.items():
        assert name in parts and set(parts) <= set(lab.PARTS)


def test_the_report_lists_every_step_with_a_check(lab, monkeypatch, tmp_path, capsys):
    lab.write_tfvars(
        {"project_id": P, "github_repo_id": "0", "admin_emails": ["a@example.com"], "lab_parts": ["start"]}
    )
    monkeypatch.setattr(lab, "REPORT", tmp_path / "report.txt")
    monkeypatch.setattr(lab, "cloud_from_settings", lambda: make_cloud(lab))
    monkeypatch.setattr(lab, "own_repo", lambda: None)
    with pytest.raises(SystemExit):
        lab.check(["--report"])
    report = (tmp_path / "report.txt").read_text()
    for step in lab.CHECKS:
        assert re.search(rf"^step {step} ", report, re.M), step
    assert json.dumps(P)[1:-1] in report
