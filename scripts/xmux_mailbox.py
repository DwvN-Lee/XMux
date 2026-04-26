#!/usr/bin/env python3
"""Provider-neutral XMux mailbox storage and CLI.

Storage root defaults to $XMUX_HOME or the current project's .codex/xmux:

  <root>/teams/<team>/
    team.json
    inboxes/<name>.json
    requests/<request_id>.json
    events.jsonl
"""
import argparse
import datetime
import json
import os
import sys
import tempfile
import time
import uuid
from pathlib import Path

_SCRIPTS = Path(__file__).resolve().parent
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))
from _filelock import file_lock, sigterm_guard  # noqa: E402


SCHEMA_TEAM = "xmux.team.v1"
SCHEMA_REQUEST = "xmux.request.v1"


class MailboxError(Exception):
    """Raised for mailbox usage or storage errors."""


def now_ts() -> str:
    now = datetime.datetime.now(datetime.timezone.utc)
    return now.strftime("%Y-%m-%dT%H:%M:%S.") + f"{now.microsecond // 1000:03d}Z"


def store_root(root=None) -> Path:
    if root is not None:
        return Path(root).expanduser()
    env_root = os.environ.get("XMUX_HOME")
    if env_root:
        return Path(env_root).expanduser()
    return _project_root(Path.cwd()) / ".codex" / "xmux"


def _project_root(start: Path) -> Path:
    path = start.expanduser().resolve()
    for candidate in (path, *path.parents):
        if (candidate / ".git").exists():
            return candidate
    return path


def _safe_component(value: str, field: str) -> str:
    if value is None:
        raise MailboxError(f"{field} is required")
    text = str(value).strip()
    if not text or text in {".", ".."}:
        raise MailboxError(f"{field} must be a non-empty path component")
    if "/" in text or "\\" in text:
        raise MailboxError(f"{field} must not contain path separators")
    return text


def team_dir(team: str, root=None) -> Path:
    team_name = _safe_component(team, "team")
    return store_root(root) / "teams" / team_name


def _team_json_path(team: str, root=None) -> Path:
    return team_dir(team, root) / "team.json"


def _inbox_path(team: str, owner: str, root=None) -> Path:
    owner_name = _safe_component(owner, "inbox owner")
    return team_dir(team, root) / "inboxes" / f"{owner_name}.json"


def _request_path(team: str, request_id: str, root=None) -> Path:
    req_id = _safe_component(request_id, "request_id")
    return team_dir(team, root) / "requests" / f"{req_id}.json"


def _events_path(team: str, root=None) -> Path:
    return team_dir(team, root) / "events.jsonl"


def _ensure_team_dirs(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    (path / "inboxes").mkdir(exist_ok=True)
    (path / "requests").mkdir(exist_ok=True)


def _read_json(path: Path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return default
    except json.JSONDecodeError as e:
        raise MailboxError(f"invalid JSON in {path}: {e}") from e


def _atomic_write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with sigterm_guard():
        with tempfile.NamedTemporaryFile(
            mode="w",
            dir=str(path.parent),
            delete=False,
            suffix=".tmp",
            encoding="utf-8",
        ) as tf:
            json.dump(data, tf, indent=2, sort_keys=True, ensure_ascii=True)
            tf.write("\n")
            tmp_name = tf.name
        os.replace(tmp_name, path)


def _write_json_locked(path: Path, data) -> None:
    with file_lock(str(path)):
        _atomic_write_json(path, data)


def _update_json_locked(path: Path, default, updater):
    with file_lock(str(path)):
        data = _read_json(path, default)
        result = updater(data)
        _atomic_write_json(path, data)
        return result


def _ensure_json_array(path: Path) -> None:
    if path.exists():
        return

    def updater(data):
        if not isinstance(data, list):
            raise MailboxError(f"{path} is not a JSON array")
        return None

    _update_json_locked(path, [], updater)


def _ensure_text_file(path: Path) -> None:
    if path.exists():
        return
    with file_lock(str(path)):
        path.parent.mkdir(parents=True, exist_ok=True)
        if not path.exists():
            with sigterm_guard():
                with open(path, "a", encoding="utf-8"):
                    pass


def _read_team(team: str, root=None) -> dict:
    path = _team_json_path(team, root)
    data = _read_json(path, None)
    if data is None:
        raise MailboxError(f"team not initialized: {team}")
    if not isinstance(data, dict):
        raise MailboxError(f"{path} is not a JSON object")
    return data


def _lead_name(team: str, root=None) -> str:
    data = _read_team(team, root)
    lead = data.get("lead") or {}
    name = lead.get("name")
    if not name:
        raise MailboxError(f"team has no lead name: {team}")
    return name


def _append_event(team: str, event: str, *, root=None, actor=None, target=None,
                  request_id=None, data=None) -> None:
    path = _events_path(team, root)
    path.parent.mkdir(parents=True, exist_ok=True)
    record = {
        "ts": now_ts(),
        "event": event,
        "actor": actor,
        "target": target,
        "request_id": request_id,
        "data": data or {},
    }
    line = json.dumps(record, sort_keys=True, ensure_ascii=True) + "\n"
    with file_lock(str(path)):
        with sigterm_guard():
            with open(path, "a", encoding="utf-8") as f:
                f.write(line)


def _append_inbox(team: str, owner: str, entry: dict, root=None) -> None:
    path = _inbox_path(team, owner, root)

    def updater(data):
        if not isinstance(data, list):
            raise MailboxError(f"{path} is not a JSON array")
        data.append(entry)
        return None

    _update_json_locked(path, [], updater)


def _mark_lead_responses_read(team: str, request_id: str, root=None) -> int:
    lead = _lead_name(team, root)
    path = _inbox_path(team, lead, root)

    def updater(data):
        if not isinstance(data, list):
            raise MailboxError(f"{path} is not a JSON array")
        marked = 0
        for entry in data:
            if (
                entry.get("type") == "response"
                and entry.get("request_id") == request_id
                and not entry.get("read", False)
            ):
                entry["read"] = True
                entry["read_at"] = now_ts()
                marked += 1
        return marked

    return _update_json_locked(path, [], updater)


def mark_inbox_read(team: str, owner: str, timestamp=None, request_id=None,
                    root=None) -> dict:
    owner_name = _safe_component(owner, "owner")
    ts = str(timestamp or "")
    req_id = str(request_id or "")
    path = _inbox_path(team, owner_name, root)

    def entry_request_id(entry):
        value = entry.get("request_id") or entry.get("requestId") or ""
        if value:
            return value
        raw_text = entry.get("text", entry.get("message", ""))
        if not isinstance(raw_text, str):
            return ""
        try:
            nested = json.loads(raw_text)
        except Exception:
            return ""
        if isinstance(nested, dict):
            return nested.get("request_id") or nested.get("requestId") or ""
        return ""

    def updater(data):
        if not isinstance(data, list):
            raise MailboxError(f"{path} is not a JSON array")
        marked = 0
        for entry in data:
            if not isinstance(entry, dict) or entry.get("read", False):
                continue
            if ts and entry.get("timestamp") == ts:
                entry["read"] = True
            elif req_id and entry_request_id(entry) == req_id:
                entry["read"] = True
            elif not ts and not req_id:
                entry["read"] = True
            else:
                continue
            entry["read_at"] = now_ts()
            marked += 1
            if ts or req_id:
                break
        return marked

    marked = _update_json_locked(path, [], updater)
    return {
        "status": "ok",
        "team": _safe_component(team, "team"),
        "owner": owner_name,
        "marked": marked,
    }


def init_team(team: str, lead_name: str, lead_provider: str, lead_pane=None,
              root=None) -> dict:
    tdir = team_dir(team, root)
    _ensure_team_dirs(tdir)
    team_name = _safe_component(team, "team")
    lead = _safe_component(lead_name, "lead_name")
    provider = _safe_component(lead_provider, "lead_provider")
    path = tdir / "team.json"
    created = now_ts()

    def updater(data):
        if data is None:
            data = {}
        if not isinstance(data, dict):
            raise MailboxError(f"{path} is not a JSON object")
        data.setdefault("schema", SCHEMA_TEAM)
        data.setdefault("name", team_name)
        data.setdefault("created_at", created)
        data["updated_at"] = created
        data["lead"] = {
            "name": lead,
            "provider": provider,
            "pane": lead_pane,
            "registered_at": data.get("lead", {}).get("registered_at", created),
            "updated_at": created,
        }
        members = data.setdefault("members", {})
        existing = members.get(lead, {})
        members[lead] = {
            "name": lead,
            "role": "lead",
            "provider": provider,
            "backend": existing.get("backend", provider),
            "pane": lead_pane,
            "registered_at": existing.get("registered_at", created),
            "updated_at": created,
            "active": True,
        }
        return data

    with file_lock(str(path)):
        data = _read_json(path, None)
        data = updater(data)
        _atomic_write_json(path, data)

    _ensure_json_array(_inbox_path(team, lead, root))
    _ensure_text_file(tdir / "events.jsonl")
    _append_event(
        team,
        "team.initialized",
        root=root,
        actor=lead,
        data={"lead_provider": provider, "lead_pane": lead_pane},
    )
    return {
        "status": "ok",
        "team": team_name,
        "team_dir": str(tdir),
        "lead_name": lead,
        "lead_provider": provider,
    }


def register_member(team: str, name: str, provider: str, pane=None,
                    backend="tmux", root=None) -> dict:
    tdir = team_dir(team, root)
    if not (tdir / "team.json").exists():
        raise MailboxError(f"team not initialized: {team}")
    member = _safe_component(name, "name")
    provider_name = _safe_component(provider, "provider")
    if provider_name not in {"claude", "gemini", "copilot"}:
        raise MailboxError(
            "teammate provider must be one of: claude, gemini, copilot"
        )
    backend_name = _safe_component(backend, "backend")
    path = tdir / "team.json"
    updated = now_ts()

    def updater(data):
        if not isinstance(data, dict):
            raise MailboxError(f"{path} is not a JSON object")
        members = data.setdefault("members", {})
        existing = members.get(member, {})
        members[member] = {
            "name": member,
            "role": existing.get("role", "member"),
            "provider": provider_name,
            "backend": backend_name,
            "pane": pane,
            "registered_at": existing.get("registered_at", updated),
            "updated_at": updated,
            "active": True,
        }
        data["updated_at"] = updated
        return members[member]

    result = _update_json_locked(path, None, updater)
    _ensure_json_array(_inbox_path(team, member, root))
    _append_event(
        team,
        "member.registered",
        root=root,
        actor=member,
        data={"provider": provider_name, "backend": backend_name, "pane": pane},
    )
    return {"status": "ok", "team": team, "member": result}


def update_member(team: str, name: str, provider=None, pane=None, backend=None,
                  session=None, display_mode=None, active=None,
                  root=None) -> dict:
    tdir = team_dir(team, root)
    if not (tdir / "team.json").exists():
        raise MailboxError(f"team not initialized: {team}")
    member = _safe_component(name, "name")
    path = tdir / "team.json"
    updated = now_ts()

    def updater(data):
        if not isinstance(data, dict):
            raise MailboxError(f"{path} is not a JSON object")
        members = data.setdefault("members", {})
        existing = members.get(member)
        if not isinstance(existing, dict):
            raise MailboxError(f"member not registered: {member}")

        changes = {}
        for key, value in (
            ("provider", provider),
            ("backend", backend),
            ("pane", pane),
            ("session", session),
            ("display_mode", display_mode),
        ):
            if value is not None:
                changes[key] = value
        if active is not None:
            changes["active"] = bool(active)
        existing.update(changes)
        existing["updated_at"] = updated
        data["updated_at"] = updated
        return existing, changes

    result, changes = _update_json_locked(path, None, updater)
    _append_event(
        team,
        "member.updated",
        root=root,
        actor=member,
        data=changes,
    )
    return {"status": "ok", "team": team, "member": result}


def enqueue_request(team: str, to: str, from_name: str, message: str,
                    request_id=None, root=None) -> dict:
    _read_team(team, root)
    target = _safe_component(to, "to")
    sender = _safe_component(from_name, "from")
    req_id = (
        _safe_component(request_id, "request_id")
        if request_id
        else uuid.uuid4().hex
    )
    ts = now_ts()
    entry_id = f"msg-{uuid.uuid4().hex}"
    entry = {
        "id": entry_id,
        "type": "request",
        "request_id": req_id,
        "from": sender,
        "to": target,
        "text": message,
        "timestamp": ts,
        "read": False,
        "status": "pending",
    }
    req = {
        "schema": SCHEMA_REQUEST,
        "request_id": req_id,
        "team": _safe_component(team, "team"),
        "from": sender,
        "to": target,
        "message": message,
        "status": "pending",
        "created_at": ts,
        "updated_at": ts,
        "inbox_entry_id": entry_id,
        "responses": [],
    }
    req_path = _request_path(team, req_id, root)
    with file_lock(str(req_path)):
        if req_path.exists():
            raise MailboxError(f"request already exists: {req_id}")
        _atomic_write_json(req_path, req)
    _append_inbox(team, target, entry, root)
    _append_event(
        team,
        "request.enqueued",
        root=root,
        actor=sender,
        target=target,
        request_id=req_id,
        data={"inbox_entry_id": entry_id},
    )
    return {"status": "pending", "request_id": req_id, "to": target}


def write_response(team: str, from_name: str, text: str, summary=None,
                   request_id=None, status="done", root=None) -> dict:
    if status not in {"done", "pending"}:
        raise MailboxError("status must be done or pending")
    lead = _lead_name(team, root)
    sender = _safe_component(from_name, "from")
    req_id = _safe_component(request_id, "request_id") if request_id else None
    ts = now_ts()
    response_id = f"rsp-{uuid.uuid4().hex}"
    response = {
        "id": response_id,
        "type": "response",
        "request_id": req_id,
        "from": sender,
        "to": lead,
        "text": text,
        "summary": summary,
        "timestamp": ts,
        "read": False,
        "status": status,
    }
    _append_inbox(team, lead, response, root)

    if req_id:
        path = _request_path(team, req_id, root)
        with file_lock(str(path)):
            data = _read_json(path, None)
            if data is None:
                data = {
                    "schema": SCHEMA_REQUEST,
                    "request_id": req_id,
                    "team": _safe_component(team, "team"),
                    "from": None,
                    "to": sender,
                    "message": None,
                    "created_at": ts,
                    "responses": [],
                }
            if not isinstance(data, dict):
                raise MailboxError(f"{path} is not a JSON object")
            data.setdefault("responses", [])
            data["responses"].append(response)
            data["status"] = status
            data["updated_at"] = ts
            _atomic_write_json(path, data)

    _append_event(
        team,
        "response.written",
        root=root,
        actor=sender,
        target=lead,
        request_id=req_id,
        data={"response_id": response_id, "status": status},
    )
    return {
        "status": status,
        "request_id": req_id,
        "response_id": response_id,
        "to": lead,
    }


def read_response(team: str, request_id: str, mark_read=False, root=None) -> dict:
    req_id = _safe_component(request_id, "request_id")
    path = _request_path(team, req_id, root)
    data = _read_json(path, None)
    if data is None:
        return {"status": "missing", "request_id": req_id}
    if not isinstance(data, dict):
        raise MailboxError(f"{path} is not a JSON object")
    responses = data.get("responses") or []
    done = data.get("status") == "done" and bool(responses)
    if not done:
        return {"status": "pending", "request_id": req_id}
    marked = _mark_lead_responses_read(team, req_id, root) if mark_read else 0
    result = {
        "status": "done",
        "request_id": req_id,
        "response": responses[-1],
    }
    if mark_read:
        result["marked_read"] = marked
    return result


def wait_response(team: str, request_id: str, timeout=60.0, interval=1.0,
                  mark_read=False, root=None) -> dict:
    timeout_s = max(float(timeout), 0.0)
    interval_s = max(float(interval), 0.001)
    deadline = time.monotonic() + timeout_s
    while True:
        result = read_response(team, request_id, mark_read=mark_read, root=root)
        if result["status"] in {"done", "missing"}:
            result["timed_out"] = False
            return result
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            result["timed_out"] = True
            return result
        time.sleep(min(interval_s, remaining))


def team_status(team: str, root=None) -> dict:
    tdir = team_dir(team, root)
    data = _read_json(tdir / "team.json", None)
    if data is None:
        return {"status": "missing", "team": _safe_component(team, "team")}
    if not isinstance(data, dict):
        raise MailboxError(f"{tdir / 'team.json'} is not a JSON object")

    inboxes = {}
    inbox_dir = tdir / "inboxes"
    if inbox_dir.exists():
        for path in sorted(inbox_dir.glob("*.json")):
            messages = _read_json(path, [])
            if not isinstance(messages, list):
                continue
            inboxes[path.stem] = {
                "total": len(messages),
                "unread": sum(1 for msg in messages if not msg.get("read", False)),
            }

    request_counts = {"total": 0, "pending": 0, "done": 0}
    requests_dir = tdir / "requests"
    if requests_dir.exists():
        for path in sorted(requests_dir.glob("*.json")):
            req = _read_json(path, {})
            if not isinstance(req, dict):
                continue
            request_counts["total"] += 1
            status = req.get("status", "pending")
            if status == "done":
                request_counts["done"] += 1
            else:
                request_counts["pending"] += 1

    return {
        "status": "ok",
        "team": data.get("name", _safe_component(team, "team")),
        "team_dir": str(tdir),
        "lead": data.get("lead"),
        "members": data.get("members", {}),
        "inboxes": inboxes,
        "requests": request_counts,
    }


def list_events(team: str, status=None, root=None) -> dict:
    path = _events_path(team, root)
    events = []
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    record = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if status and record.get("data", {}).get("status") != status:
                    continue
                events.append(record)
    except FileNotFoundError:
        pass
    return {
        "status": "ok",
        "team": _safe_component(team, "team"),
        "events": events,
    }


def list_requests(team: str, status=None, root=None) -> dict:
    req_dir = team_dir(team, root) / "requests"
    requests = []
    if req_dir.exists():
        for path in sorted(req_dir.glob("*.json")):
            data = _read_json(path, None)
            if not isinstance(data, dict):
                continue
            if status and data.get("status") != status:
                continue
            requests.append(data)
    return {
        "status": "ok",
        "team": _safe_component(team, "team"),
        "requests": requests,
    }


def _print_json(data) -> None:
    print(json.dumps(data, sort_keys=True, ensure_ascii=True))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="XMux mailbox core")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("init-team")
    p.add_argument("team")
    p.add_argument("--lead-name", required=True)
    p.add_argument("--lead-provider", required=True)
    p.add_argument("--lead-pane")

    p = sub.add_parser("register-member")
    p.add_argument("team")
    p.add_argument("name")
    p.add_argument("--provider", required=True)
    p.add_argument("--pane")
    p.add_argument("--backend", default="tmux")

    p = sub.add_parser("update-member")
    p.add_argument("team")
    p.add_argument("name")
    p.add_argument("--provider")
    p.add_argument("--pane")
    p.add_argument("--backend")
    p.add_argument("--session")
    p.add_argument("--display-mode")
    p.add_argument("--active", choices=["true", "false"])

    p = sub.add_parser("enqueue-request")
    p.add_argument("team")
    p.add_argument("to")
    p.add_argument("--from", dest="from_name", required=True)
    p.add_argument("--message", required=True)
    p.add_argument("--request-id")

    p = sub.add_parser("write-response")
    p.add_argument("team")
    p.add_argument("--from", dest="from_name", required=True)
    p.add_argument("--text", required=True)
    p.add_argument("--summary")
    p.add_argument("--request-id")
    p.add_argument("--status", default="done", choices=["done", "pending"])

    p = sub.add_parser("read-response")
    p.add_argument("team")
    p.add_argument("request_id")
    p.add_argument("--mark-read", action="store_true")

    p = sub.add_parser("wait-response")
    p.add_argument("team")
    p.add_argument("request_id")
    p.add_argument("--timeout", type=float, default=60.0)
    p.add_argument("--interval", type=float, default=1.0)
    p.add_argument("--mark-read", action="store_true")

    p = sub.add_parser("team-status")
    p.add_argument("team")

    p = sub.add_parser("mark-read")
    p.add_argument("team")
    p.add_argument("owner")
    p.add_argument("--timestamp")
    p.add_argument("--request-id")

    p = sub.add_parser("list-events")
    p.add_argument("team")
    p.add_argument("--status")

    p = sub.add_parser("list-requests")
    p.add_argument("team")
    p.add_argument("--status")
    return parser


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.command == "init-team":
            result = init_team(
                args.team,
                lead_name=args.lead_name,
                lead_provider=args.lead_provider,
                lead_pane=args.lead_pane,
            )
        elif args.command == "register-member":
            result = register_member(
                args.team,
                args.name,
                provider=args.provider,
                pane=args.pane,
                backend=args.backend,
            )
        elif args.command == "update-member":
            active = None
            if args.active is not None:
                active = args.active == "true"
            result = update_member(
                args.team,
                args.name,
                provider=args.provider,
                pane=args.pane,
                backend=args.backend,
                session=args.session,
                display_mode=args.display_mode,
                active=active,
            )
        elif args.command == "enqueue-request":
            result = enqueue_request(
                args.team,
                args.to,
                from_name=args.from_name,
                message=args.message,
                request_id=args.request_id,
            )
        elif args.command == "write-response":
            result = write_response(
                args.team,
                from_name=args.from_name,
                text=args.text,
                summary=args.summary,
                request_id=args.request_id,
                status=args.status,
            )
        elif args.command == "read-response":
            result = read_response(
                args.team,
                args.request_id,
                mark_read=args.mark_read,
            )
        elif args.command == "wait-response":
            result = wait_response(
                args.team,
                args.request_id,
                timeout=args.timeout,
                interval=args.interval,
                mark_read=args.mark_read,
            )
        elif args.command == "team-status":
            result = team_status(args.team)
        elif args.command == "mark-read":
            result = mark_inbox_read(
                args.team,
                args.owner,
                timestamp=args.timestamp,
                request_id=args.request_id,
            )
        elif args.command == "list-events":
            result = list_events(args.team, status=args.status)
        elif args.command == "list-requests":
            result = list_requests(args.team, status=args.status)
        else:
            raise MailboxError(f"unknown command: {args.command}")
        _print_json(result)
        return 0
    except MailboxError as e:
        print(f"xmux_mailbox: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
