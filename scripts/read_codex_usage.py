#!/usr/bin/env python3

import json
import os
import sys
from datetime import datetime
from pathlib import Path

try:
    from zoneinfo import ZoneInfo
except Exception:  # pragma: no cover
    ZoneInfo = None


MAX_RECENT_FILES = 150
TAIL_BYTES = 4 * 1024 * 1024


def local_tz():
    tz_name = os.environ.get("TZ")
    if tz_name and ZoneInfo is not None:
        try:
            return ZoneInfo(tz_name)
        except Exception:
            pass
    return datetime.now().astimezone().tzinfo


def usage_files():
    codex_home = Path(os.environ.get("CODEX_HOME", "~/.codex")).expanduser()
    sessions_dir = codex_home / "sessions"
    if not sessions_dir.exists():
        return []

    files = []
    for path in sessions_dir.rglob("*.jsonl"):
        try:
            files.append((path.stat().st_mtime, path))
        except OSError:
            continue
    files.sort(reverse=True)
    return [path for _, path in files[:MAX_RECENT_FILES]]


def candidate_lines_from_tail(path):
    try:
        with path.open("rb") as file:
            file.seek(0, os.SEEK_END)
            size = file.tell()
            file.seek(max(0, size - TAIL_BYTES), os.SEEK_SET)
            data = file.read()
    except OSError:
        return []

    return [
        line
        for line in reversed(data.splitlines())
        if b'"type":"token_count"' in line and b'"rate_limits"' in line
    ]


def candidate_lines_full(path):
    lines = []
    try:
        with path.open("rb") as file:
            for line in file:
                if b'"type":"token_count"' in line and b'"rate_limits"' in line:
                    lines.append(line)
    except OSError:
        return []
    return list(reversed(lines))


def parse_event(line, path):
    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        return None

    payload = event.get("payload") or {}
    if payload.get("type") != "token_count":
        return None

    rate_limits = payload.get("rate_limits")
    if not isinstance(rate_limits, dict):
        return None

    return {
        "timestamp": event.get("timestamp"),
        "rate_limits": rate_limits,
        "source_path": str(path),
    }


def latest_usage_event():
    latest = None

    for path in usage_files():
        lines = candidate_lines_from_tail(path)
        if not lines:
            lines = candidate_lines_full(path)

        for line in lines:
            event = parse_event(line, path)
            if event is None:
                continue
            if latest is None or (event.get("timestamp") or "") > (latest.get("timestamp") or ""):
                latest = event
            break

    return latest


def window_label(window_minutes):
    if not isinstance(window_minutes, (int, float)):
        return "Window"
    if window_minutes % 1440 == 0:
        days = int(window_minutes // 1440)
        return f"{days}d"
    if window_minutes % 60 == 0:
        hours = int(window_minutes // 60)
        return f"{hours}h"
    return f"{int(window_minutes)}m"


def reset_label(seconds, tz, include_date=False):
    if not isinstance(seconds, (int, float)):
        return "unknown"

    dt = datetime.fromtimestamp(seconds, tz)
    now = datetime.now(tz)
    if include_date or dt.date() != now.date():
        return dt.strftime("%b %-d")
    return dt.strftime("%-I:%M %p")


def rate_limit_summary(label, limit, tz):
    if not isinstance(limit, dict):
        return f"{label}: unavailable"

    used = limit.get("used_percent")
    reset = limit.get("resets_at")
    if isinstance(used, (int, float)):
        used_text = f"{used:.0f}%"
    else:
        used_text = "--%"

    if label == "Weekly":
        reset_text = reset_label(reset, tz, include_date=True)
        return f"Weekly: {used_text} used, resets {reset_text}"

    reset_text = reset_label(reset, tz)
    return f"{label}: {used_text} used, refreshes {reset_text}"


def credits_summary(credits):
    if not isinstance(credits, dict):
        return None
    if credits.get("unlimited"):
        return "Credits: unlimited"
    balance = credits.get("balance")
    if balance is None:
        return None
    try:
        return f"Credits: {float(balance):,.2f}"
    except (TypeError, ValueError):
        return f"Credits: {balance}"


def format_updated(timestamp, tz):
    if not timestamp:
        return "Updated: unknown"
    try:
        timestamp = timestamp.replace("Z", "+00:00")
        dt = datetime.fromisoformat(timestamp).astimezone(tz)
    except ValueError:
        return f"Updated: {timestamp}"
    return "Updated: " + dt.strftime("%-I:%M:%S %p")


def build_payload(event):
    tz = local_tz()
    limits = event["rate_limits"]
    primary = limits.get("primary")

    primary_used = primary.get("used_percent") if isinstance(primary, dict) else None
    primary_reset = primary.get("resets_at") if isinstance(primary, dict) else None
    primary_reset_text = reset_label(primary_reset, tz)

    if isinstance(primary_used, (int, float)):
        menu_title = f"{primary_reset_text} | {primary_used:.0f}%"
    else:
        menu_title = "--"

    plan_type = limits.get("plan_type")
    plan_summary = f"Plan: {plan_type}" if plan_type else None

    return {
        "ok": True,
        "menu_title": menu_title,
        "primary_used_percent": primary_used,
        "primary_resets_at": primary_reset,
        "primary_summary": rate_limit_summary("Codex", primary, tz),
        "credits_summary": credits_summary(limits.get("credits")),
        "plan_summary": plan_summary,
        "updated_summary": format_updated(event.get("timestamp"), tz),
        "source_summary": "Source: " + Path(event["source_path"]).name,
    }


def main():
    event = latest_usage_event()
    if event is None:
        print(json.dumps({
            "ok": False,
            "menu_title": "--",
            "primary_summary": "Codex usage: unavailable",
            "updated_summary": "Updated: no local token-count event found",
            "error": "No Codex usage event found under ~/.codex/sessions",
        }))
        return 1

    print(json.dumps(build_payload(event)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
