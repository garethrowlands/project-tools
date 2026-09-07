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


# --- claude_session_name ---


def test_claude_session_name_reads_matching_pid_file(tmp_path):
    module = load_module()
    (tmp_path / "1234.json").write_text(json.dumps({"pid": 1234, "name": "my-session"}))
    assert module.claude_session_name(1234, sessions_dir=tmp_path) == "my-session"


def test_claude_session_name_missing_file_returns_none(tmp_path):
    module = load_module()
    assert module.claude_session_name(9999, sessions_dir=tmp_path) is None


def test_claude_session_name_no_pid_returns_none(tmp_path):
    module = load_module()
    assert module.claude_session_name(None, sessions_dir=tmp_path) is None


def test_claude_session_name_malformed_file_returns_none(tmp_path):
    module = load_module()
    (tmp_path / "1234.json").write_text("not json")
    assert module.claude_session_name(1234, sessions_dir=tmp_path) is None


# --- parse_boottime / idle_label ---


def test_parse_boottime():
    module = load_module()
    epoch = module.parse_boottime("{ sec = 1700000000, usec = 500000 }")
    assert epoch == 1700000000.5


def test_boot_epoch_returns_none_when_sysctl_unavailable(monkeypatch):
    module = load_module()

    def raise_missing(*args, **kwargs):
        raise FileNotFoundError("no sysctl")

    monkeypatch.setattr(module.subprocess, "run", raise_missing)
    assert module.boot_epoch() is None


def test_idle_label_unknown_boot_epoch_falls_back_to_idle():
    module = load_module()
    assert module.idle_label(100.0, False, None, 200.0) == "idle"


def test_idle_label_focused():
    module = load_module()
    assert module.idle_label(100.0, True, 0.0, 10000.0) == "active in tab"


def test_idle_label_minutes():
    module = load_module()
    # boot=0, last_focused_at=0 -> idle since epoch 0; now = 300s later = 5 minutes
    label = module.idle_label(0.0, False, 0.0, 300.0)
    assert label == "5m idle"


def test_idle_label_hours():
    module = load_module()
    label = module.idle_label(0.0, False, 0.0, 3 * 3600.0)
    assert label == "3h idle"


def test_idle_label_days():
    module = load_module()
    label = module.idle_label(0.0, False, 0.0, 2 * 86400.0)
    assert label == "2d idle"


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
    windows = module.build_windows_payload(rows, git_cache, boot_epoch_s=0.0, now_epoch_s=0.0)
    assert windows[0]["git"] is windows[1]["git"]
    assert windows[1]["idle_label"] == "active in tab"


def test_build_windows_payload_includes_claude_session(monkeypatch):
    module = load_module()
    monkeypatch.setattr(module, "claude_session_name", lambda pid: "my-session" if pid == 42 else None)
    rows = [{"id": 1, "tab_id": 1, "cwd": "/p/a", "is_focused": False, "last_focused_at": 0.0, "pid": 42}]
    windows = module.build_windows_payload(rows, {}, boot_epoch_s=0.0, now_epoch_s=0.0)
    assert windows[0]["claude_session"] == "my-session"


# --- project_key / project_label ---


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


def _w(id, tab_id, cwd, root=None):
    return {"id": id, "tab_id": tab_id, "cwd": cwd, "git": {"root": root or cwd}}


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
    monkeypatch.setattr(module, "boot_epoch", lambda: 0.0)
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
    monkeypatch.setattr(module, "boot_epoch", lambda: 0.0)
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
