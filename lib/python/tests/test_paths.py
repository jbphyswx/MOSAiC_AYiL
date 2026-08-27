"""Tests for repo/run path resolution."""

from __future__ import annotations

from pathlib import Path

from ayil.paths import find_repo_root, resolve_run_dir


def test_find_repo_root() -> None:
    root = find_repo_root()
    assert (root / "ayil_config_input_results").is_dir()
    assert (root / "scripts" / "reproduce.sh").is_file()


def test_resolve_run_dir_relative() -> None:
    root = find_repo_root()
    run = resolve_run_dir("runs/20200720", repo_root=root)
    assert run.is_absolute()
    assert run.name == "20200720"
    assert run.parent.name == "runs"
