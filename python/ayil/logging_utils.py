"""Logging setup for the ayil CLI."""

from __future__ import annotations

import logging
import sys
from pathlib import Path


def setup_logging(
    *,
    verbose: bool = False,
    quiet: bool = False,
    log_file: Path | None = None,
) -> logging.Logger:
    """Configure package logger; return ``ayil`` root logger for this process."""
    if verbose and quiet:
        raise ValueError("cannot use both verbose and quiet")

    level = (
        logging.DEBUG
        if verbose
        else logging.WARNING
        if quiet
        else logging.INFO
    )

    log = logging.getLogger("ayil")
    log.handlers.clear()
    log.setLevel(level)
    log.propagate = False

    fmt = logging.Formatter(
        "%(asctime)s %(levelname)s %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    stderr = logging.StreamHandler(sys.stderr)
    stderr.setLevel(level)
    stderr.setFormatter(fmt)
    log.addHandler(stderr)

    if log_file is not None:
        log_file = Path(log_file)
        log_file.parent.mkdir(parents=True, exist_ok=True)
        fh = logging.FileHandler(log_file, encoding="utf-8")
        fh.setLevel(level)
        fh.setFormatter(fmt)
        log.addHandler(fh)

    return log


def human_bytes(n: int) -> str:
    """Format byte count for log lines."""
    x = float(n)
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if x < 1024.0 or unit == "TiB":
            if unit == "B":
                return f"{int(x)} {unit}"
            return f"{x:.2f} {unit}"
        x /= 1024.0
    return f"{n} B"
