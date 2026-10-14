"""Tests for the tidy-windows-advise `advise` script."""

import json
import subprocess
import sys
from importlib.machinery import SourceFileLoader
import importlib.util
from pathlib import Path
from unittest.mock import MagicMock

SCRIPT = Path(__file__).parent.parent / "advise"


def load_module():
    loader = SourceFileLoader("advise", str(SCRIPT))
    spec = importlib.util.spec_from_loader("advise", loader)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_script(args: list[str], input: str = "") -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(SCRIPT)] + args,
        input=input,
        capture_output=True,
        text=True,
    )


def make_mock_client(result: dict) -> MagicMock:
    block = MagicMock()
    block.type = "text"
    block.text = json.dumps(result)
    response = MagicMock()
    response.content = [block]
    client = MagicMock()
    client.messages.create.return_value = response
    return client


def make_kitty_ls(windows_by_tab: dict[int, list[dict]], tab_titles: dict[int, str] | None = None) -> list:
    tab_titles = tab_titles or {}
    tabs = []
    for tab_id, windows in windows_by_tab.items():
        tabs.append(
            {
                "id": tab_id,
                "title": tab_titles.get(tab_id, f"tab{tab_id}"),
                "windows": windows,
            }
        )
    return [{"tabs": tabs}]


def make_window(id, cwd, cmdline=None, is_focused=False, is_self=False, last_focused_at=0.0, title="win", pid=None):
    return {
        "id": id,
        "title": title,
        "is_focused": is_focused,
        "is_self": is_self,
        "last_focused_at": last_focused_at,
        "foreground_processes": [{"cwd": cwd, "cmdline": cmdline or ["-zsh"], "pid": pid}],
    }


# --- build_rows ---


def test_build_rows_excludes_self():
    module = load_module()
    ls = make_kitty_ls({1: [make_window(1, "/p/a"), make_window(2, "/p/a", is_self=True)]})
    rows = module.build_rows(ls)
    assert [r["id"] for r in rows] == [1]


def test_build_rows_excludes_null_cwd():
    module = load_module()
    ls = make_kitty_ls({1: [make_window(1, None)]})
    rows = module.build_rows(ls)
    assert rows == []


def test_build_rows_maps_fields_including_tab_id():
    module = load_module()
    ls = make_kitty_ls({7: [make_window(1, "/p/a", cmdline=["nvim"], is_focused=True, last_focused_at=12.5, pid=4242)]},
                        tab_titles={7: "myproj"})
    rows = module.build_rows(ls)
    row = rows[0]
    assert row["id"] == 1
    assert row["tab_id"] == 7
    assert row["tab_title"] == "myproj"
    assert row["cwd"] == "/p/a"
    assert row["cmdline"] == ["nvim"]
    assert row["is_focused"] is True
    assert row["last_focused_at"] == 12.5
    assert row["pid"] == 4242
    assert row["proc"] == "nvim"
    assert row["seen_at"] is None


def test_build_rows_reads_seen_at_user_var():
    module = load_module()
    window = {**make_window(1, "/p/a"), "user_vars": {"seen_at": "1700000000"}}
    assert module.build_rows(make_kitty_ls({7: [window]}))[0]["seen_at"] == "1700000000"


def test_running_commands_empty_at_a_shell_prompt():
    module = load_module()
    assert module.running_commands([{"cmdline": ["-zsh"]}]) == []
    assert module.running_commands([{}]) == []


def test_running_commands_lists_non_shell_processes_once():
    module = load_module()
    fg = [{"cmdline": ["/x/esbuild", "--service", "--ping"]}, {"cmdline": ["node", "likec4", "dev"]},
          {"cmdline": ["node", "worker"]}]
    assert module.running_commands(fg) == ["esbuild", "node"]


def test_running_commands_empty_for_a_forgotten_picker():
    module = load_module()
    fg = [{"cmdline": ["fzf", "--ansi"]}, {"cmdline": ["zsh", "/x/bin/window"]}, {"cmdline": ["zsh", "/x/bin/window"]}]
    assert module.running_commands(fg) == []


def test_running_commands_empty_for_a_claude_window():
    module = load_module()
    fg = [{"cmdline": ["glab", "mcp", "serve"]}, {"cmdline": ["caffeinate", "-i"]}, {"cmdline": ["claude"]}]
    assert module.running_commands(fg) == []


def test_build_rows_lists_every_foreground_process():
    module = load_module()
    window = make_window(1, "/p/a")
    window["foreground_processes"] = [{"cwd": "/p/a", "cmdline": ["esbuild", "--service"]},
                                      {"cwd": "/p/a", "cmdline": ["node", "likec4", "dev"]}]
    row = module.build_rows(make_kitty_ls({7: [window]}))[0]
    assert row["processes"] == ["esbuild --service", "node likec4 dev"]
    assert row["running"] == ["esbuild", "node"]


def test_build_rows_marks_overlays_from_tab_groups():
    module = load_module()
    ls = make_kitty_ls({7: [make_window(1, "/p/a"), make_window(2, "/p/a"), make_window(3, "/p/b")]})
    ls[0]["tabs"][0]["groups"] = [{"id": 10, "windows": [2, 1]}, {"id": 11, "windows": [3]}]  # kitty lists the overlay first
    assert [r["is_overlay"] for r in module.build_rows(ls)] == [False, True, False]


def test_build_rows_no_overlays_without_groups():
    module = load_module()
    assert module.build_rows(make_kitty_ls({7: [make_window(1, "/p/a")]}))[0]["is_overlay"] is False


# --- claude_session_name ---


def make_config_dir(base: Path, name: str = ".claude") -> Path:
    config_dir = base / name
    (config_dir / "sessions").mkdir(parents=True)
    (config_dir / "projects").mkdir(parents=True)
    return config_dir


def write_session(config_dir: Path, pid: int, **fields) -> Path:
    path = config_dir / "sessions" / f"{pid}.json"
    path.write_text(json.dumps({"pid": pid, **fields}))
    return path


def write_transcript(config_dir: Path, session_id: str, ai_titles: list[str]) -> Path:
    project_dir = config_dir / "projects" / "some-project"
    project_dir.mkdir(parents=True, exist_ok=True)
    path = project_dir / f"{session_id}.jsonl"
    lines = [json.dumps({"type": "ai-title", "aiTitle": title}) for title in ai_titles]
    path.write_text("\n".join(lines) + "\n" if lines else "")
    return path


def test_claude_session_name_prefers_ai_title_over_name_slug(tmp_path):
    module = load_module()
    config_dir = make_config_dir(tmp_path)
    write_session(config_dir, 1234, sessionId="sid-1", name="project-tools-8f")
    write_transcript(config_dir, "sid-1", ["first draft title", "Window switcher fzf colors"])
    assert module.claude_session_name(1234, config_dirs=[config_dir]) == "Window switcher fzf colors"


def test_claude_session_name_falls_back_to_name_slug_without_ai_title(tmp_path):
    module = load_module()
    config_dir = make_config_dir(tmp_path)
    write_session(config_dir, 1234, sessionId="sid-1", name="project-tools-8f")
    assert module.claude_session_name(1234, config_dirs=[config_dir]) == "project-tools-8f"


def test_claude_session_name_follows_parked_job_id(tmp_path):
    module = load_module()
    config_dir = make_config_dir(tmp_path)
    # interactive session, parked on a background job, with no ai-title of its own yet
    write_session(config_dir, 7121, sessionId="sid-interactive", name="context-e1", parkedJobId="job-1")
    write_transcript(config_dir, "sid-interactive", [])
    # the background job's own session, with a descriptive name
    write_session(config_dir, 13848, sessionId="sid-job", name="sources/ publishing design", jobId="job-1")
    assert module.claude_session_name(7121, config_dirs=[config_dir]) == "sources/ publishing design"


def test_claude_session_name_prefers_own_ai_title_over_parked_job(tmp_path):
    module = load_module()
    config_dir = make_config_dir(tmp_path)
    write_session(config_dir, 7121, sessionId="sid-interactive", name="context-e1", parkedJobId="job-1")
    write_transcript(config_dir, "sid-interactive", ["actual title"])
    write_session(config_dir, 13848, sessionId="sid-job", name="sources/ publishing design", jobId="job-1")
    assert module.claude_session_name(7121, config_dirs=[config_dir]) == "actual title"


def test_claude_session_name_searches_multiple_config_dirs(tmp_path):
    module = load_module()
    default_dir = make_config_dir(tmp_path, ".claude")
    work_dir = make_config_dir(tmp_path, ".claude-k")
    write_session(work_dir, 9999, sessionId="sid-work", name="work-slug")
    assert module.claude_session_name(9999, config_dirs=[default_dir, work_dir]) == "work-slug"


def test_claude_session_name_missing_file_returns_none(tmp_path):
    module = load_module()
    config_dir = make_config_dir(tmp_path)
    assert module.claude_session_name(9999, config_dirs=[config_dir]) is None


def test_claude_session_name_no_pid_returns_none(tmp_path):
    module = load_module()
    config_dir = make_config_dir(tmp_path)
    assert module.claude_session_name(None, config_dirs=[config_dir]) is None


def test_claude_session_name_malformed_file_returns_none(tmp_path):
    module = load_module()
    config_dir = make_config_dir(tmp_path)
    (config_dir / "sessions" / "1234.json").write_text("not json")
    assert module.claude_session_name(1234, config_dirs=[config_dir]) is None


def test_claude_session_name_prefers_newest_file_across_config_dirs(tmp_path):
    import os

    module = load_module()
    default_dir = make_config_dir(tmp_path, ".claude")
    work_dir = make_config_dir(tmp_path, ".claude-k")
    stale = write_session(default_dir, 9999, name="stale-slug")
    write_session(work_dir, 9999, name="live-slug")
    os.utime(stale, (1, 1))
    assert module.claude_session_name(9999, config_dirs=[default_dir, work_dir]) == "live-slug"


# --- agent state ---


def test_agent_state_table():
    module = load_module()
    assert module.agent_state("waiting", 200, "100", False) == "blocked"
    assert module.agent_state("busy", 200, "100", False) == "working"
    assert module.agent_state("idle", 200, "100", False) == "done"
    assert module.agent_state("shell", 200, "100", False) == "done"
    assert module.agent_state("idle", 50, "100", False) == "idle"
    assert module.agent_state("idle", 200, "100", True) == "idle"  # you're looking at it
    assert module.agent_state("idle", 200, None, False) == "idle"  # watcher never saw the window
    assert module.agent_state("something-new", 200, "100", False) is None


def test_claude_agent_state_reads_session_file(tmp_path):
    module = load_module()
    config_dir = make_config_dir(tmp_path)
    write_session(config_dir, 1234, status="idle", statusUpdatedAt=200_000)
    assert module.claude_agent_state(1234, "100", False, config_dirs=[config_dir]) == "done"
    assert module.claude_agent_state(1234, "300", False, config_dirs=[config_dir]) == "idle"


def test_claude_agent_state_missing_or_malformed_is_none(tmp_path):
    module = load_module()
    config_dir = make_config_dir(tmp_path)
    assert module.claude_agent_state(1234, "100", False, config_dirs=[config_dir]) is None
    (config_dir / "sessions" / "1234.json").write_text("not json")
    assert module.claude_agent_state(1234, "100", False, config_dirs=[config_dir]) is None
    write_session(config_dir, 1235, status="idle", statusUpdatedAt="soon")
    assert module.claude_agent_state(1235, "100", False, config_dirs=[config_dir]) is None


# --- kitty_now / idle_seconds / idle_label ---


def test_kitty_now_is_newest_last_focused_at_including_self():
    module = load_module()
    ls = make_kitty_ls({1: [make_window(1, "/p/a", last_focused_at=100.0)],
                        2: [make_window(2, "/p/b", last_focused_at=250.5, is_self=True)]})
    assert module.kitty_now(ls) == 250.5


def test_kitty_now_none_without_any_stamp():
    module = load_module()
    window = make_window(1, "/p/a")
    del window["last_focused_at"]
    assert module.kitty_now(make_kitty_ls({1: [window]})) is None


def test_idle_seconds_prefers_seen_at():
    module = load_module()
    assert module.idle_seconds(100.0, "1000", 400.0, 1600.0) == 600


def test_idle_seconds_falls_back_to_kitty_clock():
    module = load_module()
    assert module.idle_seconds(100.0, None, 400.0, 1600.0) == 300.0
    assert module.idle_seconds(100.0, "not-a-number", 400.0, 1600.0) == 300.0


def test_idle_seconds_unknown_without_either():
    module = load_module()
    assert module.idle_seconds(None, None, 400.0, 1600.0) is None
    assert module.idle_seconds(100.0, None, None, 1600.0) is None


def test_idle_seconds_never_negative():
    module = load_module()
    assert module.idle_seconds(500.0, None, 400.0, 1600.0) == 0
    assert module.idle_seconds(None, "2000", None, 1600.0) == 0


def test_idle_label_unknown_falls_back_to_idle():
    module = load_module()
    assert module.idle_label(None, False) == "idle"


def test_idle_label_focused():
    module = load_module()
    assert module.idle_label(10000.0, True) == "active in tab"


def test_idle_label_minutes():
    module = load_module()
    assert module.idle_label(300.0, False) == "5m idle"
    assert module.idle_label(5.0, False) == "1m idle"


def test_idle_label_hours():
    module = load_module()
    assert module.idle_label(3 * 3600.0, False) == "3h idle"


def test_idle_label_days():
    module = load_module()
    assert module.idle_label(2 * 86400.0, False) == "2d idle"


# --- git_summary ---


def run_git(cwd, *args):
    subprocess.run(["git", "-C", str(cwd), *args], check=True, capture_output=True)


def init_repo(tmp_path) -> Path:
    repo = tmp_path / "repo"
    repo.mkdir()
    run_git(repo, "init", "-q", "-b", "main")
    run_git(repo, "config", "user.email", "test@example.com")
    run_git(repo, "config", "user.name", "Test")
    (repo / "file.txt").write_text("hello\n")
    run_git(repo, "add", ".")
    run_git(repo, "commit", "-q", "-m", "initial")
    return repo


def test_git_summary_clean_repo(tmp_path):
    module = load_module()
    repo = init_repo(tmp_path)
    summary = module.git_summary(str(repo))
    assert summary["root"] == str(repo.resolve())
    assert summary["branch"] == "main"
    assert summary["dirty"] is False
    assert "no commits" not in summary["last_commit_relative"]


def test_git_summary_dirty_repo(tmp_path):
    module = load_module()
    repo = init_repo(tmp_path)
    (repo / "file.txt").write_text("changed\n")
    summary = module.git_summary(str(repo))
    assert summary["dirty"] is True


def test_git_summary_subdirectory_reports_repo_root(tmp_path):
    module = load_module()
    repo = init_repo(tmp_path)
    subdir = repo / "sub"
    subdir.mkdir()
    summary = module.git_summary(str(subdir))
    assert summary["root"] == str(repo.resolve())


def test_git_summary_worktree_belongs_to_the_main_repo(tmp_path):
    module = load_module()
    repo = init_repo(tmp_path)
    worktree = tmp_path / "repo-feature"
    run_git(repo, "worktree", "add", "-q", str(worktree), "-b", "feature")
    summary = module.git_summary(str(worktree))
    assert summary["root"] == str(worktree.resolve())
    assert summary["branch"] == "feature"
    assert summary["project_root"] == str(repo.resolve())
    assert module.git_summary(str(repo))["project_root"] == str(repo.resolve())


def test_git_summary_non_git_dir_returns_none(tmp_path):
    module = load_module()
    plain = tmp_path / "plain"
    plain.mkdir()
    assert module.git_summary(str(plain)) is None


# --- build_windows_payload ---


def test_build_windows_payload_merges_and_dedupes_git(tmp_path):
    module = load_module()
    rows = [
        {"id": 1, "tab_id": 1, "cwd": "/p/a", "is_focused": False, "last_focused_at": 0.0},
        {"id": 2, "tab_id": 1, "cwd": "/p/a", "is_focused": True, "last_focused_at": 0.0},
    ]
    git_cache = {"/p/a": {"root": "/p/a", "branch": "main"}}
    windows = module.build_windows_payload(rows, git_cache, kitty_now_s=0.0, now_epoch_s=0.0)
    assert windows[0]["git"] is windows[1]["git"]
    assert windows[1]["idle_label"] == "active in tab"


def test_build_windows_payload_includes_claude_session(monkeypatch):
    module = load_module()
    monkeypatch.setattr(module, "claude_session_name", lambda pid: "my-session" if pid == 42 else None)
    rows = [{"id": 1, "tab_id": 1, "cwd": "/p/a", "is_focused": False, "last_focused_at": 0.0, "pid": 42, "proc": "claude"}]
    windows = module.build_windows_payload(rows, {}, kitty_now_s=0.0, now_epoch_s=0.0)
    assert windows[0]["claude_session"] == "my-session"


def test_build_windows_payload_skips_claude_session_lookup_for_non_claude_proc(monkeypatch):
    module = load_module()
    monkeypatch.setattr(module, "claude_session_name", lambda pid: "my-session")
    rows = [{"id": 1, "tab_id": 1, "cwd": "/p/a", "is_focused": False, "last_focused_at": 0.0, "pid": 42, "proc": "vim"}]
    windows = module.build_windows_payload(rows, {}, kitty_now_s=0.0, now_epoch_s=0.0)
    assert windows[0]["claude_session"] is None


def test_build_windows_payload_includes_claude_state(monkeypatch):
    module = load_module()
    monkeypatch.setattr(module, "claude_session_name", lambda pid: None)
    calls = []

    def fake_state(pid, seen_at, looked_at):
        calls.append((pid, seen_at, looked_at))
        return "done"

    monkeypatch.setattr(module, "claude_agent_state", fake_state)
    base = {"cwd": "/p/a", "last_focused_at": 0.0, "is_focused": False, "seen_at": "100"}
    rows = [
        {**base, "id": 1, "pid": 41, "proc": "claude"},
        {**base, "id": 2, "pid": 42, "proc": "claude"},
        {**base, "id": 3, "pid": 43, "proc": "zsh"},
    ]
    windows = module.build_windows_payload(rows, {}, kitty_now_s=0.0, now_epoch_s=0.0, current_window_id=2)
    assert [w["claude_state"] for w in windows] == ["done", "done", None]
    assert calls == [(41, "100", False), (42, "100", True)]


# --- project_key / project_label ---


def test_project_key_groups_a_worktree_with_its_main_repo():
    module = load_module()
    w = {"cwd": "/p/a-feature/sub", "git": {"root": "/p/a-feature", "project_root": "/p/a"}}
    assert module.project_key(w) == "/p/a"
    assert module.project_label(w) == "a"


def test_project_key_uses_git_root():
    module = load_module()
    w = {"cwd": "/p/a/sub", "git": {"root": "/p/a"}}
    assert module.project_key(w) == "/p/a"
    assert module.project_label(w) == "a"


def test_project_key_falls_back_to_cwd_without_git():
    module = load_module()
    w = {"cwd": "/p/nogit", "git": None}
    assert module.project_key(w) == "/p/nogit"
    assert module.project_label(w) == "nogit"


# --- plan_moves ---


def _w(id, tab_id, cwd, root=None, tab_title="", project_root=None):
    git = {"root": root or cwd}
    if project_root:
        git["project_root"] = project_root
    return {"id": id, "tab_id": tab_id, "tab_title": tab_title, "cwd": cwd, "git": git}


def test_plan_moves_single_tab_project_no_move():
    module = load_module()
    windows = [_w(1, 1, "/p/a"), _w(2, 1, "/p/a")]
    assert module.plan_moves(windows) == {}


def test_plan_moves_splits_across_tabs_moves_minority():
    module = load_module()
    windows = [_w(1, 1, "/p/a"), _w(2, 1, "/p/a"), _w(3, 2, "/p/a")]
    moves = module.plan_moves(windows)
    assert moves == {3: 1}


def test_plan_moves_tie_break_lowest_tab_id():
    module = load_module()
    windows = [_w(1, 5, "/p/a"), _w(2, 2, "/p/a")]
    moves = module.plan_moves(windows)
    assert moves == {1: 2}


def test_plan_moves_no_move_when_no_shared_tab():
    module = load_module()
    windows = [_w(1, 1, "/p/a"), _w(2, 2, "/p/b")]
    assert module.plan_moves(windows) == {}


def test_plan_moves_tab_titled_for_project_is_home_even_with_fewer_windows():
    module = load_module()
    windows = [_w(1, 1, "/p/a", tab_title="a"), _w(2, 2, "/p/a"), _w(3, 2, "/p/a")]
    assert module.plan_moves(windows) == {2: 1, 3: 1}


def test_plan_moves_matches_tab_title_by_last_path_component():
    module = load_module()
    windows = [_w(1, 1, "/p/a", tab_title="github.com/me/a"), _w(2, 2, "/p/a"), _w(3, 2, "/p/a")]
    assert module.plan_moves(windows) == {2: 1, 3: 1}


def test_plan_moves_stray_window_in_other_projects_tab_goes_to_a_new_tab():
    module = load_module()
    windows = [_w(1, 1, "/p/bar", tab_title="bar"), _w(2, 1, "/p/bar"), _w(3, 1, "/p/foo")]
    assert module.plan_moves(windows) == {3: "new:foo"}


def test_plan_moves_all_of_a_projects_strays_share_one_new_tab():
    module = load_module()
    windows = [_w(1, 1, "/p/bar", tab_title="bar"), _w(2, 1, "/p/foo"), _w(3, 1, "/p/foo")]
    assert module.plan_moves(windows) == {2: "new:foo", 3: "new:foo"}


def test_plan_moves_leaves_a_mixed_untitled_tab_alone_when_nothing_owns_it():
    module = load_module()
    windows = [_w(1, 1, "/p/bar"), _w(2, 1, "/p/foo"), _w(3, 2, "/p/baz")]
    assert module.plan_moves(windows) == {}


def test_plan_moves_tab_titled_for_another_project_is_not_a_home():
    module = load_module()
    windows = [_w(1, 1, "/p/bar", tab_title="bar"), _w(2, 1, "/p/foo"), _w(3, 2, "/p/foo")]
    assert module.plan_moves(windows) == {2: 2}


def test_plan_moves_worktree_window_goes_to_main_projects_tab():
    module = load_module()
    windows = [
        _w(1, 1, "/p/a", tab_title="a"),
        _w(2, 2, "/p/a/.claude/worktrees/x", root="/p/a/.claude/worktrees/x", project_root="/p/a"),
    ]
    assert module.plan_moves(windows) == {2: 1}


# --- advise / OUTPUT_SCHEMA ---


def make_windows_payload():
    return [
        {
            "id": 1,
            "cwd": "/p/a",
            "cmdline": ["-zsh"],
            "is_focused": False,
            "idle_label": "3h idle",
            "git": {"root": "/p/a", "branch": "main", "dirty": False, "ahead": 0, "behind": 0,
                     "last_commit_relative": "3 days ago"},
            "claude_session": "debugging-auth",
        }
    ]


def test_advise_calls_messages_create_once_with_model():
    module = load_module()
    windows = make_windows_payload()
    client = make_mock_client({"recommendations": [{"id": 1, "action": "close", "reason": "stale"}]})

    result = module.advise(windows, "claude-haiku-4-5-20251001", client)

    client.messages.create.assert_called_once()
    assert client.messages.create.call_args.kwargs["model"] == "claude-haiku-4-5-20251001"
    assert result == {"recommendations": [{"id": 1, "action": "close", "reason": "stale"}]}


def test_advise_prompt_contains_window_data():
    module = load_module()
    windows = make_windows_payload()
    client = make_mock_client({"recommendations": []})

    module.advise(windows, "claude-haiku-4-5-20251001", client)

    content = client.messages.create.call_args.kwargs["messages"][0]["content"]
    assert "/p/a" in content
    assert "3h idle" in content
    assert "debugging-auth" in content


def test_advise_uses_json_schema_output_config():
    module = load_module()
    client = make_mock_client({"recommendations": []})
    module.advise(make_windows_payload(), "claude-haiku-4-5-20251001", client)

    output_config = client.messages.create.call_args.kwargs["output_config"]
    assert output_config["format"]["type"] == "json_schema"
    schema = output_config["format"]["schema"]
    assert schema["properties"]["recommendations"]["items"]["properties"]["action"]["enum"] == ["close", "keep"]
    assert schema["properties"]["recommendations"]["items"]["additionalProperties"] is False


# --- merge_actions ---


def test_merge_actions_close_wins_over_pending_move():
    module = load_module()
    windows = [{"id": 1, "cwd": "/p/a", "idle_label": "1h idle", "git": None}]
    recs = {"recommendations": [{"id": 1, "action": "close", "reason": "stale"}]}
    moves = {1: 2}
    result = module.merge_actions(windows, recs, moves)
    assert result[0]["action"] == "close"
    assert result[0]["reason"] == "stale"


def test_a_move_survives_a_close_that_a_protection_overrides():
    module = load_module()
    windows = [{"id": 1, "cwd": "/p/a", "idle_label": "1h idle", "git": None, "running": ["node"]}]
    recs = {"recommendations": [{"id": 1, "action": "close", "reason": "stale"}]}
    rows = module.protect_running_processes(module.merge_actions(windows, recs, {1: 2}))
    assert rows[0]["action"] == "move"
    assert rows[0]["target_tab"] == 2


def test_an_active_agent_that_is_not_to_be_closed_is_still_moved():
    module = load_module()
    windows = [{"id": 1, "cwd": "/p/a", "idle_label": "x", "git": None, "claude_state": "working"}]
    recs = {"recommendations": [{"id": 1, "action": "close", "reason": "stale"}]}
    rows = module.protect_active_agents(module.merge_actions(windows, recs, {1: "new:a"}))
    assert (rows[0]["action"], rows[0]["target_tab"]) == ("move", "new:a")


def test_to_fzf_tsv_names_a_new_tab():
    module = load_module()
    rows = [{"id": 1, "action": "move", "target_tab": "new:foo", "reason": "r", "label": "x"}]
    assert module.to_fzf_tsv(rows).split("\t")[:3] == ["1", "move", "new:foo"]
    assert "new foo tab" in module.to_fzf_tsv(rows)


def test_merge_actions_move_applies_when_kept():
    module = load_module()
    windows = [{"id": 1, "cwd": "/p/a", "idle_label": "1h idle", "git": None}]
    recs = {"recommendations": [{"id": 1, "action": "keep", "reason": "active work"}]}
    moves = {1: 2}
    result = module.merge_actions(windows, recs, moves)
    assert result[0]["action"] == "move"
    assert result[0]["target_tab"] == 2


def test_merge_actions_plain_keep():
    module = load_module()
    windows = [{"id": 1, "cwd": "/p/a", "idle_label": "1h idle", "git": None}]
    recs = {"recommendations": [{"id": 1, "action": "keep", "reason": "active work"}]}
    result = module.merge_actions(windows, recs, {})
    assert result[0]["action"] == "keep"
    assert result[0]["reason"] == "active work"


def test_merge_actions_unknown_id_defaults_to_keep():
    module = load_module()
    windows = [{"id": 1, "cwd": "/p/a", "idle_label": "1h idle", "git": None}]
    result = module.merge_actions(windows, {"recommendations": []}, {})
    assert result[0]["action"] == "keep"
    assert result[0]["reason"] == module.NO_RECOMMENDATION


def test_merge_actions_label_includes_claude_session_when_present():
    module = load_module()
    windows = [{"id": 1, "cwd": "/p/a", "idle_label": "1h idle", "git": None, "claude_session": "my-session"}]
    result = module.merge_actions(windows, {"recommendations": []}, {})
    assert "[my-session]" in result[0]["label"]


def test_merge_actions_label_omits_bracket_when_no_claude_session():
    module = load_module()
    windows = [{"id": 1, "cwd": "/p/a", "idle_label": "1h idle", "git": None, "claude_session": None}]
    result = module.merge_actions(windows, {"recommendations": []}, {})
    assert "[" not in result[0]["label"]


def test_merge_actions_label_marks_agent_state():
    module = load_module()
    base = {"cwd": "/p/a", "idle_label": "1h idle", "git": None, "claude_session": "my-session"}
    windows = [{**base, "id": 1, "claude_state": "blocked"}, {**base, "id": 2, "claude_state": "idle"}]
    result = module.merge_actions(windows, {"recommendations": []}, {})
    assert result[0]["label"].endswith("(1h idle) ! [my-session]")
    assert result[1]["label"].endswith("(1h idle) [my-session]")
    assert [r["claude_state"] for r in result] == ["blocked", "idle"]


# --- protect_active_agents ---


def test_protect_active_agents_overrides_close():
    module = load_module()
    for state in ("working", "blocked", "done"):
        rows = [{"id": 1, "action": "close", "target_tab": None, "reason": "stale", "label": "x", "claude_state": state}]
        result = module.protect_active_agents(rows)
        assert result[0]["action"] == "keep"
        assert result[0]["reason"] == module.ACTIVE_AGENT_REASONS[state]


def test_protect_active_agents_leaves_idle_and_non_claude_closes():
    module = load_module()
    rows = [
        {"id": 1, "action": "close", "target_tab": None, "reason": "stale", "label": "x", "claude_state": "idle"},
        {"id": 2, "action": "close", "target_tab": None, "reason": "stale", "label": "y", "claude_state": None},
    ]
    assert [r["action"] for r in module.protect_active_agents(rows)] == ["close", "close"]


def test_protect_active_agents_leaves_moves_alone():
    module = load_module()
    rows = [{"id": 1, "action": "move", "target_tab": 2, "reason": "r", "label": "x", "claude_state": "working"}]
    result = module.protect_active_agents(rows)
    assert result[0]["action"] == "move"
    assert result[0]["target_tab"] == 2


def test_merge_actions_label_names_what_is_running():
    module = load_module()
    windows = [{"id": 1, "cwd": "/p/a", "idle_label": "1h idle", "git": None, "running": ["esbuild", "node"]}]
    result = module.merge_actions(windows, {"recommendations": []}, {})
    assert result[0]["label"].endswith("(1h idle) (esbuild, node)")
    assert result[0]["running"] == ["esbuild", "node"]


def test_merge_actions_always_closes_an_overlay():
    module = load_module()
    windows = [{"id": 1, "cwd": "/p/a", "idle_label": "1h idle", "git": None, "is_overlay": True, "running": ["less"]}]
    recs = {"recommendations": [{"id": 1, "action": "keep", "reason": "looks busy"}]}
    result = module.merge_actions(windows, recs, {1: 2})
    assert result[0]["action"] == "close"
    assert result[0]["reason"] == module.OVERLAY_REASON
    assert "(overlay) (less)" in result[0]["label"]
    # ...and running something doesn't save it
    assert module.protect_running_processes(result)[0]["action"] == "close"


def test_overlay_with_an_active_agent_is_still_kept():
    module = load_module()
    windows = [{"id": 1, "cwd": "/p/a", "idle_label": "1h idle", "git": None, "is_overlay": True, "claude_state": "working"}]
    result = module.protect_active_agents(module.merge_actions(windows, {}, {}))
    assert result[0]["action"] == "keep"


# --- protect_running_processes ---


def test_protect_running_processes_overrides_close():
    module = load_module()
    rows = [{"id": 1, "action": "close", "target_tab": None, "reason": "stale", "label": "x", "running": ["node"]}]
    result = module.protect_running_processes(rows)
    assert result[0]["action"] == "keep"
    assert "running node" in result[0]["reason"]


def test_protect_running_processes_leaves_shell_windows_and_moves_alone():
    module = load_module()
    rows = [
        {"id": 1, "action": "close", "target_tab": None, "reason": "stale", "label": "x", "running": []},
        {"id": 2, "action": "move", "target_tab": 3, "reason": "r", "label": "y", "running": ["node"]},
    ]
    assert [r["action"] for r in module.protect_running_processes(rows)] == ["close", "move"]


def test_advise_prompt_lists_all_processes():
    module = load_module()
    window = {"id": 1, "cwd": "/p/a", "cmdline": ["esbuild"], "processes": ["esbuild --service", "node likec4 dev"],
              "is_focused": False, "idle_label": "1h idle", "git": None}
    assert "node likec4 dev" in module.build_prompt([window])


# --- protect_current_window ---


def test_protect_current_window_overrides_close():
    module = load_module()
    rows = [{"id": 1, "action": "close", "target_tab": None, "reason": "stale", "label": "proj > win (idle)"}]
    result = module.protect_current_window(rows, 1)
    assert result[0]["action"] == "keep"
    assert result[0]["target_tab"] is None
    assert result[0]["reason"] == module.CURRENT_WINDOW_REASON
    assert module.CURRENT_WINDOW_MARKER in result[0]["label"]


def test_protect_current_window_overrides_move():
    module = load_module()
    rows = [{"id": 1, "action": "move", "target_tab": 2, "reason": "consolidate", "label": "proj > win (idle)"}]
    result = module.protect_current_window(rows, 1)
    assert result[0]["action"] == "keep"
    assert result[0]["target_tab"] is None


def test_protect_current_window_leaves_other_rows_alone():
    module = load_module()
    rows = [
        {"id": 1, "action": "close", "target_tab": None, "reason": "stale", "label": "a"},
        {"id": 2, "action": "keep", "target_tab": None, "reason": "active", "label": "b"},
    ]
    result = module.protect_current_window(rows, 2)
    assert result[0]["action"] == "close"
    assert result[1]["action"] == "keep"
    assert result[1]["reason"] == module.CURRENT_WINDOW_REASON


def test_protect_current_window_none_is_noop():
    module = load_module()
    rows = [{"id": 1, "action": "close", "target_tab": None, "reason": "stale", "label": "a"}]
    result = module.protect_current_window(rows, None)
    assert result[0]["action"] == "close"
    assert result[0]["reason"] == "stale"


def test_protect_current_window_unmatched_id_is_noop():
    module = load_module()
    rows = [{"id": 1, "action": "close", "target_tab": None, "reason": "stale", "label": "a"}]
    result = module.protect_current_window(rows, 999)
    assert result[0]["action"] == "close"


# --- to_fzf_tsv / render_dry_run ---


def test_to_fzf_tsv_excludes_keep_rows():
    module = load_module()
    rows = [
        {"id": 1, "action": "keep", "target_tab": None, "reason": "", "label": "a"},
        {"id": 2, "action": "close", "target_tab": None, "reason": "", "label": "b"},
    ]
    lines = module.to_fzf_tsv(rows).splitlines()
    assert len(lines) == 1
    assert lines[0].startswith("2\t")


def test_to_fzf_tsv_all_kept_yields_empty_string():
    module = load_module()
    rows = [{"id": 1, "action": "keep", "target_tab": None, "reason": "", "label": "a"}]
    assert module.to_fzf_tsv(rows) == ""


def test_to_fzf_tsv_sorts_by_label():
    module = load_module()
    rows = [
        {"id": 1, "action": "move", "target_tab": 9, "reason": "", "label": "z-project"},
        {"id": 2, "action": "close", "target_tab": None, "reason": "", "label": "a-project"},
    ]
    lines = module.to_fzf_tsv(rows).splitlines()
    assert lines[0].startswith("2\t")
    assert lines[1].startswith("1\t")


def test_to_fzf_tsv_columns():
    module = load_module()
    rows = [{"id": 5, "action": "move", "target_tab": 3, "reason": "consolidate", "label": "proj"}]
    line = module.to_fzf_tsv(rows)
    cols = line.split("\t")
    assert cols[0] == "5"
    assert cols[1] == "move"
    assert cols[2] == "3"
    assert "MOVE" in cols[3]


def test_render_dry_run_contains_reason():
    module = load_module()
    rows = [{"id": 1, "action": "close", "target_tab": None, "reason": "very stale", "label": "proj"}]
    assert "very stale" in module.render_dry_run(rows)


# --- main() graceful degradation ---


def test_main_falls_back_to_keep_when_advise_raises_dry_run(tmp_path, monkeypatch, capsys):
    module = load_module()
    repo = init_repo(tmp_path)
    ls = make_kitty_ls({1: [make_window(1, str(repo))]})
    ls_path = tmp_path / "ls.json"
    ls_path.write_text(json.dumps(ls))

    monkeypatch.setattr(module.anthropic, "Anthropic", MagicMock(side_effect=RuntimeError("no key")))
    monkeypatch.setattr(sys, "argv", ["advise", "--kitty-ls", str(ls_path), "--dry-run"])

    module.main()
    out = capsys.readouterr().out
    assert "keep" in out
    assert "close" not in out.split("\t")[1:2]  # no close action present


# --- CLI validation (subprocess) ---


def test_cli_reads_kitty_ls_from_file(tmp_path):
    ls = make_kitty_ls({1: []})
    ls_path = tmp_path / "ls.json"
    ls_path.write_text(json.dumps(ls))
    result = run_script(["--kitty-ls", str(ls_path)])
    assert result.returncode == 0
    assert result.stdout == ""
    assert "no open windows to review" in result.stderr


def test_main_prints_stderr_message_when_nothing_actionable(tmp_path, monkeypatch, capsys):
    """All windows recommended "keep" - to_fzf_tsv's output is empty, but the user should
    still get a clear "reviewed, nothing to do" message rather than silence."""
    module = load_module()
    repo = init_repo(tmp_path)
    ls = make_kitty_ls({1: [make_window(1, str(repo))]})
    ls_path = tmp_path / "ls.json"
    ls_path.write_text(json.dumps(ls))

    monkeypatch.setattr(module.anthropic, "Anthropic", MagicMock(side_effect=RuntimeError("no key")))
    monkeypatch.setattr(sys, "argv", ["advise", "--kitty-ls", str(ls_path)])

    module.main()
    captured = capsys.readouterr()
    assert captured.out == ""
    assert "nothing to close or move" in captured.err


def test_cli_default_model_is_haiku():
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--kitty-ls")
    parser.add_argument("--model", default="claude-haiku-4-5-20251001")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args([])
    assert args.model == "claude-haiku-4-5-20251001"
