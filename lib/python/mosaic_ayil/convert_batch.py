"""Discover runs and decide whether fielddump → Zarr conversion is needed."""

from __future__ import annotations

import logging
import re
from pathlib import Path
from typing import Any

from ayil.convert import AYiL_COMPLETE, AYiL_RUNNING, convert_run
from ayil.convert_stamps import fielddump_newer_than_zarr
from ayil.fielddump import fielddump_has_snapshots, find_fielddump_tiles

_DATE_DIR = re.compile(r"^\d{8}$")


def is_run_active(run_dir: Path) -> bool:
    """True when DALES is marked running and the day is not complete."""
    return (run_dir / AYiL_RUNNING).is_file() and not (run_dir / AYiL_COMPLETE).is_file()


def discover_run_dirs(runs_root: Path) -> list[Path]:
    """Sorted ``runs/YYYYMMDD`` directories that contain fielddump tiles."""
    runs_root = Path(runs_root)
    if not runs_root.is_dir():
        return []

    out: list[Path] = []
    for child in sorted(runs_root.iterdir()):
        if not child.is_dir() or not _DATE_DIR.match(child.name):
            continue
        if find_fielddump_tiles(child):
            out.append(child)
    return out


def convert_runs_batch(
    run_dirs: list[Path],
    *,
    expnr: str = "001",
    overwrite: bool = False,
    update_if_stale: bool = True,
    require_complete: bool = False,
    skip_active: bool = True,
    repo_root: Path | None = None,
    log: logging.Logger | None = None,
    **convert_kwargs: Any,
) -> dict[str, list[str]]:
    """
    Convert many run directories. Returns lists of paths by outcome.
    """
    log = log or logging.getLogger("ayil")
    results: dict[str, list[str]] = {
        "converted": [],
        "updated": [],
        "skipped": [],
        "skipped_active": [],
        "skipped_no_tiles": [],
        "skipped_no_snapshots": [],
        "failed": [],
    }

    for run_dir in run_dirs:
        run_dir = Path(run_dir).resolve()
        label = str(run_dir)

        if skip_active and is_run_active(run_dir):
            log.info("Skip %s (still running)", label)
            results["skipped_active"].append(label)
            continue

        if not find_fielddump_tiles(run_dir, expnr=expnr):
            log.info("Skip %s (no fielddump tiles)", label)
            results["skipped_no_tiles"].append(label)
            continue

        if not fielddump_has_snapshots(run_dir, expnr=expnr):
            log.info(
                "Skip %s (fielddump tiles present but time dimension is empty)",
                label,
            )
            results["skipped_no_snapshots"].append(label)
            continue

        out = run_dir / "data.zarr"
        needs_write = overwrite or fielddump_newer_than_zarr(run_dir, out, expnr=expnr)

        if not needs_write:
            log.info("Skip %s (data.zarr up to date)", label)
            results["skipped"].append(label)
            continue

        was_existing = out.exists()
        try:
            convert_run(
                run_dir,
                expnr=expnr,
                overwrite=True,
                require_complete=require_complete,
                repo_root=repo_root,
                log=log,
                **convert_kwargs,
            )
        except Exception as exc:
            log.error("Failed %s: %s", label, exc)
            results["failed"].append(label)
            continue

        if was_existing:
            log.info("Updated %s", label)
            results["updated"].append(label)
        else:
            log.info("Converted %s", label)
            results["converted"].append(label)

    return results
