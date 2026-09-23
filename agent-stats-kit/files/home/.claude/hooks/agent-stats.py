#!/usr/bin/env python3
"""Claude Code hook keeping <project>/.agent-tool-stats.md up to date.

Registered for UserPromptSubmit, PostToolUse, Stop and SessionEnd; the payload
arrives as JSON on stdin (session_id, cwd, hook_event_name, and for PostToolUse
tool_name). Authoritative per-session counters live as JSON in the gitignored
<project>/.claude/.agent-stats/ directory; the markdown file is a rendering of
that state merged into the existing document, one block per session delimited by
HTML comment markers so a re-render replaces only its own span.

Every path exits 0 — broken stats must never disturb the agent.
"""

import datetime
import json
import os
import re
import subprocess
import sys
import tempfile

try:
    import fcntl
except ImportError:  # non-POSIX, locking is then a no-op
    fcntl = None

STATS_FILE = ".agent-tool-stats.md"
STATE_DIR = os.path.join(".claude", ".agent-stats")
GITIGNORE_ENTRY = ".claude/.agent-stats/"
HEADER = "# Agent tool stats"
NO_TITLE = "(task description unavailable)"
TITLE_MAX = 100


# --- helpers ---------------------------------------------------------------

def log(root, message):
    """Best-effort diagnostic; never raises."""
    try:
        path = os.path.join(root, STATE_DIR, "agent-stats.log")
        with open(path, "a", encoding="utf-8") as fh:
            fh.write("%s %s\n" % (datetime.datetime.now().isoformat(timespec="seconds"), message))
    except Exception:
        pass


def project_root(payload):
    cwd = payload.get("cwd") or os.getcwd()
    return os.path.abspath(cwd)


def safe_session_id(payload):
    sid = str(payload.get("session_id") or "").strip()
    sid = re.sub(r"[^A-Za-z0-9._-]", "", sid)
    return sid[:64]


def state_path(root, sid):
    return os.path.join(root, STATE_DIR, sid + ".json")


def ensure_state_dir(root):
    path = os.path.join(root, STATE_DIR)
    os.makedirs(path, exist_ok=True)
    return path


def ensure_gitignore(root):
    """Keep the state dir out of git; the stats file itself stays tracked."""
    path = os.path.join(root, ".gitignore")
    try:
        if os.path.exists(path):
            with open(path, "r", encoding="utf-8") as fh:
                body = fh.read()
            if any(line.strip() == GITIGNORE_ENTRY.rstrip("/") or line.strip() == GITIGNORE_ENTRY
                   for line in body.splitlines()):
                return
            prefix = "" if body == "" or body.endswith("\n") else "\n"
        else:
            body, prefix = "", ""
        with open(path, "a", encoding="utf-8") as fh:
            fh.write("%s%s\n" % (prefix, GITIGNORE_ENTRY))
    except Exception:
        pass


def derive_title(prompt):
    text = re.sub(r"\s+", " ", str(prompt or "")).strip()
    if not text:
        return NO_TITLE
    match = re.search(r"^(.+?[.!?])(\s|$)", text)
    if match:
        text = match.group(1)
    text = text.replace("|", "/").replace("<", "(").replace(">", ")")
    if len(text) > TITLE_MAX:
        text = text[:TITLE_MAX].rstrip() + "…"
    return text or NO_TITLE


def load_state(root, sid):
    try:
        with open(state_path(root, sid), "r", encoding="utf-8") as fh:
            state = json.load(fh)
    except Exception:
        return None
    if not isinstance(state, dict):
        return None
    state.setdefault("started_at", now_stamp())
    state.setdefault("title", NO_TITLE)
    counts = state.get("counts")
    state["counts"] = counts if isinstance(counts, dict) else {}
    return state


def save_state(root, sid, state):
    ensure_state_dir(root)
    write_atomic(state_path(root, sid), json.dumps(state, indent=2, sort_keys=True) + "\n")


def now_stamp():
    return datetime.datetime.now().strftime("%Y-%m-%d %H:%M")


def write_atomic(path, text):
    directory = os.path.dirname(path) or "."
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".agent-stats-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


class Lock(object):
    """flock on <state-dir>/lock so concurrent PostToolUse hooks serialise."""

    def __init__(self, root):
        self.root = root
        self.fh = None

    def __enter__(self):
        if fcntl is None:
            return self
        try:
            ensure_state_dir(self.root)
            self.fh = open(os.path.join(self.root, STATE_DIR, "lock"), "a+")
            fcntl.flock(self.fh, fcntl.LOCK_EX)
        except Exception:
            self.fh = None
        return self

    def __exit__(self, *exc):
        if self.fh is not None:
            try:
                fcntl.flock(self.fh, fcntl.LOCK_UN)
            finally:
                self.fh.close()
                self.fh = None
        return False


# --- rendering -------------------------------------------------------------

def render_block(sid, state):
    counts = state.get("counts") or {}
    rows = sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))
    lines = [
        "<!-- agent-stats:session:%s -->" % sid,
        "## %s - %s" % (state.get("started_at") or now_stamp(), state.get("title") or NO_TITLE),
        "",
        "| Tool | Invocations |",
        "| --- | --- |",
    ]
    for name, count in rows:
        lines.append("| %s | %d |" % (str(name).replace("|", "\\|"), count))
    if not rows:
        lines.append("| _(no tool used yet)_ | 0 |")
    lines += ["", "**Total:** %d" % sum(counts.values()), "<!-- /agent-stats:session:%s -->" % sid]
    return "\n".join(lines)


def merge_block(document, sid, block):
    start = "<!-- agent-stats:session:%s -->" % sid
    end = "<!-- /agent-stats:session:%s -->" % sid
    if not document.strip():
        document = HEADER + "\n"
    i = document.find(start)
    j = document.find(end)
    if i != -1 and j != -1 and j > i:
        return document[:i] + block + document[j + len(end):]
    if not document.endswith("\n"):
        document += "\n"
    return document + "\n" + block + "\n"


def write_stats(root, sid, state):
    path = os.path.join(root, STATS_FILE)
    try:
        with open(path, "r", encoding="utf-8") as fh:
            document = fh.read()
    except Exception:
        document = ""
    write_atomic(path, merge_block(document, sid, render_block(sid, state)))
    return path


# --- git -------------------------------------------------------------------

def git(root, args):
    """Run git with an argument list — never a shell string."""
    return subprocess.run(
        ["git", "-C", root] + args,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    ).returncode


def stage_stats(root):
    """Track the file in git. Staging only — committing stays a human decision."""
    try:
        if git(root, ["rev-parse", "--is-inside-work-tree"]) != 0:
            return
        if git(root, ["check-ignore", "-q", "--", STATS_FILE]) == 0:
            return
        git(root, ["add", "--", STATS_FILE])
    except Exception:
        pass


# --- events ----------------------------------------------------------------

def on_prompt(root, sid, payload):
    state = load_state(root, sid)
    if state is None:
        state = {"started_at": now_stamp(), "title": derive_title(payload.get("prompt")), "counts": {}}
    elif state.get("title") in (None, "", NO_TITLE):
        state["title"] = derive_title(payload.get("prompt"))
    save_state(root, sid, state)
    write_stats(root, sid, state)


def on_tool(root, sid, payload):
    state = load_state(root, sid)
    if state is None:
        # Kit installed mid-session: no UserPromptSubmit was ever seen.
        state = {"started_at": now_stamp(), "title": NO_TITLE, "counts": {}}
    tool = str(payload.get("tool_name") or "unknown").strip() or "unknown"
    state["counts"][tool] = int(state["counts"].get(tool, 0)) + 1
    save_state(root, sid, state)
    write_stats(root, sid, state)


def on_end(root, sid, payload):
    state = load_state(root, sid)
    if state is None:
        return
    write_stats(root, sid, state)
    stage_stats(root)


def main():
    try:
        payload = json.loads(sys.stdin.read() or "{}")
        if not isinstance(payload, dict):
            return
        root = project_root(payload)
        sid = safe_session_id(payload)
        if not sid:
            return
        event = str(payload.get("hook_event_name") or "")
        handler = {
            "UserPromptSubmit": on_prompt,
            "PostToolUse": on_tool,
            "Stop": on_end,
            "SessionEnd": on_end,
        }.get(event)
        if handler is None:
            return
        ensure_state_dir(root)
        ensure_gitignore(root)
        with Lock(root):
            handler(root, sid, payload)
    except Exception as exc:  # stats must never break the agent
        try:
            log(project_root({}), "%s: %s" % (type(exc).__name__, exc))
        except Exception:
            pass


if __name__ == "__main__":
    main()
    sys.exit(0)
