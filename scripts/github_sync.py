#!/usr/bin/env python3
"""One-way sync: docs/tasks + docs/backlog -> GitHub issues, milestones, labels, Project.

The md files are the source of truth. Issues are a read-only mirror: edits made
on GitHub are overwritten on the next run.

Usage:
    python3 scripts/github_sync.py            # sync
    python3 scripts/github_sync.py --dry-run  # print the plan, change nothing

Needs `gh` logged in with the `repo` and `project` scopes.
"""

from __future__ import annotations

import argparse
import json
import posixpath
import re
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

REPO = "funduck/my-reader"
OWNER = REPO.split("/")[0]
BRANCH = "main"
PROJECT_TITLE = "My reader"
ROOT = Path(__file__).resolve().parent.parent
BLOB = f"https://github.com/{REPO}/blob/{BRANCH}/"

# Project "Status" options, in board column order.
STATUSES = [
    ("Бэклог", "GRAY", "Открытый вопрос или идея, не запланировано"),
    ("К работе", "BLUE", "Задача ждёт агента или человека"),
    ("В работе", "YELLOW", "Начато, сделано частично"),
    ("Ждёт", "ORANGE", "Нужна проверка или замер человеком"),
    ("Отложена", "PURPLE", "Решили отложить"),
    ("В задачах", "PINK", "Вопрос из бэклога разложен на задачи T-*"),
    ("Готово", "GREEN", "Сделано"),
]
CLOSED_STATUSES = {"Готово", "В задачах"}
STREAM_FIELD = "Поток"

LABEL_KIND = {"T": ("задача", "1d76db"), "U": ("проверка", "d93f0b"), "B": ("бэклог", "cccccc")}
STREAM_COLOR = "c5def5"
BACKLOG_TYPE_COLOR = "fef2c0"
MARKER = "<!-- github_sync -->"


@dataclass
class Item:
    id: str
    title: str
    path: Path
    status_raw: str
    status: str
    stream: str | None = None
    milestone: str | None = None
    backlog_type: str | None = None
    body_md: str = ""
    labels: list[str] = field(default_factory=list)

    @property
    def issue_title(self) -> str:
        return f"{self.id}. {self.title}"

    @property
    def closed(self) -> bool:
        return self.status in CLOSED_STATUSES


# ---------------------------------------------------------------- parsing


def header_field(text: str, name: str) -> str | None:
    m = re.search(rf"^\*\*{name}:\*\*\s*(.+?)\s*$", text, re.M)
    return m.group(1) if m else None


def map_status(raw: str) -> str:
    s = raw.lower()
    if s.startswith("done"):
        return "Готово"
    if s.startswith("todo"):
        return "К работе"
    if s.startswith("отлож"):
        return "Отложена"
    if s.startswith("ждёт") or s.startswith("ждет"):
        return "Ждёт"
    if s.startswith("частично") or s.startswith("в работе"):
        return "В работе"
    if s.startswith("в задачах"):
        return "В задачах"
    if s.startswith("открыт") or s.startswith("backlog"):
        return "Бэклог"
    print(f"warning: unknown status {raw!r}, using К работе", file=sys.stderr)
    return "К работе"


LINK = re.compile(r"(\]\()([^)\s]+)(\))")


def absolutize_links(md: str, rel_dir: str) -> str:
    def fix(m: re.Match[str]) -> str:
        target = m.group(2)
        if re.match(r"^[a-z]+:", target):
            return m.group(0)
        path, _, anchor = target.partition("#")
        url = BLOB + posixpath.normpath(posixpath.join(rel_dir, path)) if path else ""
        if anchor:
            url = (url or BLOB + rel_dir) + "#" + anchor
        return m.group(1) + url + m.group(3)

    return LINK.sub(fix, md)


def parse(path: Path) -> Item | None:
    text = path.read_text(encoding="utf-8")
    m = re.match(r"# ([TUB]-\d+)\.\s+(.+)", text)
    if not m:
        print(f"warning: no '# X-NNN. Title' heading in {path}", file=sys.stderr)
        return None
    item_id, title = m.group(1), m.group(2).strip()
    status_raw = header_field(text, "Статус") or "todo"
    item = Item(item_id, title, path, status_raw, map_status(status_raw))

    stream_line = re.search(r"^\*\*Поток:\*\*.*$", text, re.M)
    if stream_line:
        for part in stream_line.group(0).split("·"):
            part = part.strip()
            if mm := re.match(r"\*\*Поток:\*\*\s*(.+)", part):
                item.stream = mm.group(1).strip()
            elif mm := re.match(r"\*\*Веха:\*\*\s*(M\d+)", part):
                item.milestone = mm.group(1)
    item.backlog_type = header_field(text, "Тип")

    kind_label = LABEL_KIND[item_id[0]][0]
    item.labels = [kind_label]
    if item.stream:
        item.labels.append(f"поток: {item.stream}")
    if item.backlog_type:
        item.labels.append(f"вид: {item.backlog_type}")

    rel = path.relative_to(ROOT).as_posix()
    rest = text[m.end():].lstrip("\n")
    item.body_md = (
        f"{MARKER}\n"
        f"> Зеркало файла [`{rel}`]({BLOB}{rel}). "
        f"Обновляется скриптом `scripts/github_sync.py`: правки здесь перезапишутся, "
        f"меняй файл.\n\n"
        + absolutize_links(rest, posixpath.dirname(rel)).rstrip()
        + "\n"
    )
    return item


def load_items() -> list[Item]:
    files = sorted((ROOT / "docs/tasks").glob("[TU]-*.md")) + sorted(
        (ROOT / "docs/backlog").glob("B-*.md")
    )
    items = [i for f in files if (i := parse(f))]
    return items


def load_milestones() -> dict[str, str]:
    """M0 -> 'M0. Каркас' from MVP-plan.md headings."""
    text = (ROOT / "docs/MVP-plan.md").read_text(encoding="utf-8")
    return {m.group(1): m.group(0)[4:].strip() for m in re.finditer(r"^### (M\d+)\..*$", text, re.M)}


# ---------------------------------------------------------------- gh helpers


DRY = False


def gh(*args: str, input_obj: object | None = None, mutate: bool = False) -> object:
    if mutate and DRY:
        print("  [dry-run] gh", " ".join(args[:4]))
        return {}
    cmd = ["gh", *args]
    for attempt in range(4):
        p = subprocess.run(
            cmd,
            input=json.dumps(input_obj) if input_obj is not None else None,
            capture_output=True,
            text=True,
        )
        if p.returncode == 0:
            return json.loads(p.stdout) if p.stdout.strip() else {}
        if "rate limit" in p.stderr.lower() and attempt < 3:
            time.sleep(30 * (attempt + 1))
            continue
        raise SystemExit(f"gh {' '.join(args)} failed:\n{p.stderr}")
    raise AssertionError


def rest(method: str, path: str, body: object | None = None) -> object:
    args = ["api", "-X", method, path]
    if body is not None:
        args += ["--input", "-"]
    return gh(*args, input_obj=body, mutate=method != "GET")


def rest_all(path: str) -> list[dict]:
    out = gh("api", "--paginate", "--slurp", path)
    return [x for page in out for x in page]  # type: ignore[union-attr]


def graphql(query: str, mutate: bool = False, **variables: object) -> dict:
    return gh("api", "graphql", "--input", "-", input_obj={"query": query, "variables": variables}, mutate=mutate)  # type: ignore[return-value]


# ---------------------------------------------------------------- sync steps


def sync_labels(items: list[Item]) -> None:
    existing = {l["name"] for l in rest_all(f"repos/{REPO}/labels?per_page=100")}
    wanted: dict[str, str] = {name: color for name, color in LABEL_KIND.values()}
    for i in items:
        for l in i.labels[1:]:
            wanted[l] = STREAM_COLOR if l.startswith("поток:") else BACKLOG_TYPE_COLOR
    for name, color in wanted.items():
        if name not in existing:
            print(f"label + {name}")
            rest("POST", f"repos/{REPO}/labels", {"name": name, "color": color})


def sync_milestones(titles: dict[str, str]) -> dict[str, dict]:
    existing = rest_all(f"repos/{REPO}/milestones?state=all&per_page=100")
    by_code = {m["title"].split(".")[0]: m for m in existing}
    out: dict[str, dict] = {}
    for code, title in titles.items():
        m = by_code.get(code)
        if m is None:
            print(f"milestone + {title}")
            m = rest("POST", f"repos/{REPO}/milestones", {"title": title}) or {"number": 0}
        elif m["title"] != title:
            print(f"milestone ~ {title}")
            rest("PATCH", f"repos/{REPO}/milestones/{m['number']}", {"title": title})
        out[code] = m
    return out


def sync_milestone_states(items: list[Item], milestones: dict[str, dict]) -> None:
    """Close a milestone when every item in it is closed; reopen otherwise."""
    for code, m in milestones.items():
        in_ms = [i for i in items if i.milestone == code]
        state = "closed" if in_ms and all(i.closed for i in in_ms) else "open"
        if m.get("state", "open") != state:
            print(f"milestone {state}: {m.get('title', code)}")
            rest("PATCH", f"repos/{REPO}/milestones/{m['number']}", {"state": state})


def fetch_issues() -> dict[str, dict]:
    issues = rest_all(f"repos/{REPO}/issues?state=all&per_page=100")
    out: dict[str, dict] = {}
    for iss in issues:
        if "pull_request" in iss:
            continue
        m = re.match(r"([TUB]-\d+)\. ", iss["title"])
        if m and MARKER in (iss.get("body") or ""):
            out[m.group(1)] = iss
    return out


def sync_issues(items: list[Item], milestones: dict[str, dict]) -> dict[str, dict]:
    issues = fetch_issues()
    for it in items:
        want = {
            "title": it.issue_title,
            "body": it.body_md,
            "labels": sorted(it.labels),
            "milestone": milestones[it.milestone]["number"] if it.milestone else None,
            "state": "closed" if it.closed else "open",
        }
        iss = issues.get(it.id)
        if iss is None:
            print(f"issue + {it.issue_title} [{it.status}]")
            created = rest("POST", f"repos/{REPO}/issues", {k: v for k, v in want.items() if k != "state"})
            if want["state"] == "closed" and created:
                rest("PATCH", f"repos/{REPO}/issues/{created['number']}", {"state": "closed", "state_reason": "completed"})
                created["state"] = "closed"
            issues[it.id] = created or {}
            time.sleep(1)  # stay under the secondary rate limit for content creation
            continue
        have = {
            "title": iss["title"],
            "body": (iss.get("body") or "").replace("\r\n", "\n"),
            "labels": sorted(l["name"] for l in iss["labels"]),
            "milestone": iss["milestone"]["number"] if iss.get("milestone") else None,
            "state": iss["state"],
        }
        diff = {k: v for k, v in want.items() if have[k] != v}
        if diff:
            print(f"issue ~ #{iss['number']} {it.id}: {', '.join(diff)}")
            if "state" in diff:
                diff["state_reason"] = "completed" if diff["state"] == "closed" else "reopened"
            updated = rest("PATCH", f"repos/{REPO}/issues/{iss['number']}", diff)
            if updated:
                issues[it.id] = updated
    return issues


# ---------------------------------------------------------------- project


def find_or_create_project() -> dict:
    projects = gh("project", "list", "--owner", OWNER, "--format", "json", "--limit", "100")
    for p in projects["projects"]:  # type: ignore[index]
        if p["title"] == PROJECT_TITLE:
            return p
    print(f"project + {PROJECT_TITLE}")
    p = gh("project", "create", "--owner", OWNER, "--title", PROJECT_TITLE, "--format", "json", mutate=True)
    if p:
        gh("project", "link", str(p["number"]), "--owner", OWNER, "--repo", REPO, mutate=True)  # type: ignore[index]
    return p  # type: ignore[return-value]


FIELDS_Q = """
query($id: ID!) { node(id: $id) { ... on ProjectV2 {
  fields(first: 50) { nodes {
    ... on ProjectV2FieldCommon { id name }
    ... on ProjectV2SingleSelectField { options { id name } }
  } }
} } }"""


def project_fields(project_id: str) -> dict[str, dict]:
    data = graphql(FIELDS_Q, id=project_id)
    return {f["name"]: f for f in data["data"]["node"]["fields"]["nodes"] if f}


def ensure_select_field(project_id: str, fields: dict[str, dict], name: str, options: list[tuple[str, str, str]]) -> None:
    opts = [{"name": n, "color": c, "description": d} for n, c, d in options]
    f = fields.get(name)
    if f is None:
        print(f"project field + {name}")
        graphql(
            """mutation($p: ID!, $n: String!, $o: [ProjectV2SingleSelectFieldOptionInput!]) {
              createProjectV2Field(input: {projectId: $p, dataType: SINGLE_SELECT, name: $n, singleSelectOptions: $o}) { clientMutationId } }""",
            mutate=True, p=project_id, n=name, o=opts,
        )
    elif [o["name"] for o in f.get("options", [])] != [o["name"] for o in opts]:
        print(f"project field ~ {name} options")
        graphql(
            """mutation($f: ID!, $o: [ProjectV2SingleSelectFieldOptionInput!]) {
              updateProjectV2Field(input: {fieldId: $f, singleSelectOptions: $o}) { clientMutationId } }""",
            mutate=True, f=f["id"], o=opts,
        )


ITEMS_Q = """
query($id: ID!, $after: String) { node(id: $id) { ... on ProjectV2 {
  items(first: 100, after: $after) {
    pageInfo { hasNextPage endCursor }
    nodes { id
      content { ... on Issue { id } }
      fieldValues(first: 20) { nodes { ... on ProjectV2ItemFieldSingleSelectValue {
        name field { ... on ProjectV2FieldCommon { name } } } } }
    }
  }
} } }"""


def project_items(project_id: str) -> dict[str, dict]:
    out: dict[str, dict] = {}
    after = None
    while True:
        page = graphql(ITEMS_Q, id=project_id, after=after)["data"]["node"]["items"]
        for n in page["nodes"]:
            if n["content"]:
                values = {v["field"]["name"]: v["name"] for v in n["fieldValues"]["nodes"] if v}
                out[n["content"]["id"]] = {"id": n["id"], "values": values}
        if not page["pageInfo"]["hasNextPage"]:
            return out
        after = page["pageInfo"]["endCursor"]


def sync_project(items: list[Item], issues: dict[str, dict]) -> str | None:
    project = find_or_create_project()
    if not project:
        return None
    pid = project["id"]
    streams = sorted({i.stream for i in items if i.stream})
    fields = project_fields(pid)
    ensure_select_field(pid, fields, "Status", STATUSES)
    ensure_select_field(pid, fields, STREAM_FIELD, [(s, "GRAY", "") for s in streams])
    fields = project_fields(pid)
    existing = project_items(pid)

    for it in items:
        iss = issues.get(it.id) or {}
        node_id = iss.get("node_id")
        if not node_id:
            continue
        entry = existing.get(node_id)
        if entry is None:
            print(f"project item + {it.id}")
            res = graphql(
                "mutation($p: ID!, $c: ID!) { addProjectV2ItemById(input: {projectId: $p, contentId: $c}) { item { id } } }",
                mutate=True, p=pid, c=node_id,
            )
            if not res:
                continue
            entry = {"id": res["data"]["addProjectV2ItemById"]["item"]["id"], "values": {}}
        for fname, value in (("Status", it.status), (STREAM_FIELD, it.stream)):
            if not value or entry["values"].get(fname) == value:
                continue
            f = fields[fname]
            option = next(o["id"] for o in f["options"] if o["name"] == value)
            graphql(
                """mutation($p: ID!, $i: ID!, $f: ID!, $o: String!) {
                  updateProjectV2ItemFieldValue(input: {projectId: $p, itemId: $i, fieldId: $f,
                    value: {singleSelectOptionId: $o}}) { clientMutationId } }""",
                mutate=True, p=pid, i=entry["id"], f=f["id"], o=option,
            )
    return project.get("url")


def main() -> None:
    global DRY
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true", help="print the plan, change nothing")
    ap.add_argument("--no-project", action="store_true", help="skip the GitHub Project step")
    args = ap.parse_args()
    DRY = args.dry_run

    items = load_items()
    print(f"{len(items)} items from docs")
    sync_labels(items)
    ms = sync_milestones(load_milestones())
    issues = sync_issues(items, ms)
    sync_milestone_states(items, ms)
    if not args.no_project:
        url = sync_project(items, issues)
        if url:
            print(f"project: {url}")


if __name__ == "__main__":
    main()
