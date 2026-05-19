"""Resolve MOSAiC_AYIL repo and run paths (no shell required)."""

from __future__ import annotations

from pathlib import Path

_REPO_MARKERS = ("ayil_config_input_results", "scripts/reproduce.sh")


def find_repo_root(start: Path | None = None) -> Path:
    """
    Walk upward from ``start`` (or this file) for a directory that looks like the repo root.
    Falls back to ``Path.cwd()`` if markers are not found.
    """
    candidates: list[Path] = []
    if start is not None:
        candidates.append(Path(start).resolve())
    here = Path(__file__).resolve()
    candidates.extend(here.parents)

    seen: set[Path] = set()
    for base in candidates:
        if base in seen:
            continue
        seen.add(base)
        if (base / "ayil_config_input_results").is_dir() and (base / "scripts").is_dir():
            return base
    return Path.cwd().resolve()


def resolve_run_dir(run_dir: Path | str, *, repo_root: Path | None = None) -> Path:
    """Turn ``runs/20200720`` or an absolute path into a resolved run directory."""
    p = Path(run_dir)
    if p.is_absolute():
        return p.resolve()
    root = repo_root if repo_root is not None else find_repo_root()
    return (root / p).resolve()


def resolve_output_path(
    output: Path | str | None,
    *,
    run_dir: Path,
    repo_root: Path | None = None,
) -> Path:
    if output is None:
        return run_dir / "data.zarr"
    p = Path(output)
    if p.is_absolute():
        return p.resolve()
    root = repo_root if repo_root is not None else find_repo_root()
    return (root / p).resolve()
