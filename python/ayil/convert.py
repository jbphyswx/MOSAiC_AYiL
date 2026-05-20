"""CLI: merge fielddump NetCDF tiles and write ``data.zarr``."""

from __future__ import annotations

import argparse
import logging
import sys
import time
from pathlib import Path

from ayil.fielddump import merge_fielddump
from ayil.logging_utils import human_bytes, setup_logging
from ayil.paths import find_repo_root, resolve_output_path, resolve_run_dir
from ayil.thermo import add_thermo_derivatives_for_run
from zarr.codecs import BloscCodec

from ayil.zarr_store import FIELDDUMP_CHUNKS_CENTER, write_dataset_zarr

AYIL_COMPLETE = ".ayil_complete"
AYIL_RUNNING = ".ayil_running"


def _check_run_ready(run_dir: Path, *, require_complete: bool, log: logging.Logger) -> None:
    complete = run_dir / AYIL_COMPLETE
    running = run_dir / AYIL_RUNNING

    if running.exists() and not complete.exists():
        raise RuntimeError(
            f"{run_dir} is still marked running ({AYIL_RUNNING}). "
            "Wait for DALES to finish or remove the stale marker."
        )

    if require_complete and not complete.exists():
        raise RuntimeError(
            f"{run_dir} has no {AYIL_COMPLETE}. "
            "Simulation may still be in progress or failed. "
            "Use --allow-incomplete to convert anyway (partial tiles may fail)."
        )

    if complete.exists():
        log.info("Run status: %s present", AYIL_COMPLETE)
    else:
        log.warning("Run status: no %s (--allow-incomplete)", AYIL_COMPLETE)


def convert_run(
    run_dir: Path,
    *,
    output: Path | None = None,
    expnr: str = "001",
    chunks_center: tuple[int, int, int, int] = FIELDDUMP_CHUNKS_CENTER,
    include_staggered: bool = True,
    include_fluxes: bool = True,
    flux_at_cell_centers: bool = True,
    add_thermo: bool = True,
    overwrite: bool = False,
    require_complete: bool = True,
    consolidated: bool = True,
    codec: BloscCodec | None = None,
    log: logging.Logger | None = None,
    repo_root: Path | None = None,
) -> Path:
    """
    Merge fielddump tiles under ``run_dir`` and write a Zarr store.

    All path resolution and progress logging happen here (not in shell).
    """
    log = log or logging.getLogger("ayil")
    run_dir = Path(run_dir).resolve()
    out = Path(output).resolve() if output else (run_dir / "data.zarr")

    if not run_dir.is_dir():
        raise FileNotFoundError(f"run directory not found: {run_dir}")

    _check_run_ready(run_dir, require_complete=require_complete, log=log)

    if out.exists() and not overwrite:
        raise FileExistsError(
            f"{out} already exists; pass --overwrite to replace"
        )

    t0 = time.perf_counter()
    log.info("Merge fielddump tiles from %s (expnr=%s)", run_dir, expnr)
    ds = merge_fielddump(
        run_dir,
        expnr=expnr,
        include_staggered=include_staggered,
        include_fluxes=include_fluxes,
        flux_at_cell_centers=flux_at_cell_centers,
        log=log,
    )
    t_merge = time.perf_counter()
    log.info(
        "Merged dataset: %s  (%d data vars, %.1f s)",
        dict(ds.sizes),
        len(ds.data_vars),
        t_merge - t0,
    )

    if add_thermo:
        root = repo_root if repo_root is not None else find_repo_root()
        log.info("Add thermo (fielddump if present, else offline from thl/ql/qt)")
        ds = add_thermo_derivatives_for_run(
            ds,
            run_dir,
            expnr=expnr,
            repo_root=root,
            log=log,
        )

    log.info(
        "Write Zarr -> %s  (center chunks=%s, staggered=%s)",
        out,
        chunks_center,
        include_staggered,
    )
    write_dataset_zarr(
        ds,
        out,
        mode="w",
        chunks_center=chunks_center,
        codec=codec,
        consolidated=consolidated,
    )
    t_done = time.perf_counter()

    try:
        zarr_bytes = sum(f.stat().st_size for f in out.rglob("*") if f.is_file())
        log.info("Zarr size on disk: %s", human_bytes(zarr_bytes))
    except OSError:
        pass

    log.info("Done in %.1f s (merge %.1f s, write %.1f s)", t_done - t0, t_merge - t0, t_done - t_merge)
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Merge DALES fielddump tiles into a single Zarr store.",
        epilog=(
            "Primary entry point (no bash required):\n"
            "  python -m ayil.convert runs/20200720\n"
            "Paths relative to the repo root are resolved automatically."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "run_dir",
        type=Path,
        help="Run directory (e.g. runs/20200720), relative to repo root or absolute",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=None,
        help="Output Zarr path (default: <run_dir>/data.zarr)",
    )
    parser.add_argument("--expnr", default="001", help="Experiment suffix (default 001)")
    parser.add_argument(
        "--no-staggered",
        action="store_true",
        help="Skip staggered wind components (u,v,w per tile)",
    )
    parser.add_argument(
        "--no-fluxes",
        action="store_true",
        help="Skip vertical flux fields (wqtt, wthlt, wqlt, wthvt)",
    )
    parser.add_argument(
        "--no-flux-centers",
        action="store_true",
        help="Keep zw fluxes only; do not add wqtt_c, wthlt_c, … on z",
    )
    parser.add_argument(
        "--no-thermo",
        action="store_true",
        help="Do not add pressure, exner, or temperature derived fields",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Replace existing Zarr store",
    )
    parser.add_argument(
        "--allow-incomplete",
        action="store_true",
        help=f"Do not require {AYIL_COMPLETE} before converting",
    )
    parser.add_argument(
        "--no-consolidated",
        action="store_true",
        help="Do not write consolidated metadata to zarr.json (slower opens)",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Debug logging (per-tile details)",
    )
    parser.add_argument(
        "-q",
        "--quiet",
        action="store_true",
        help="Only warnings and errors",
    )
    parser.add_argument(
        "--log-file",
        type=Path,
        default=None,
        help="Also write logs to this file (default: runs/20200720/logs/convert.log)",
    )
    args = parser.parse_args(argv)

    repo_root = find_repo_root()
    run_dir = resolve_run_dir(args.run_dir, repo_root=repo_root)
    output = (
        resolve_output_path(args.output, run_dir=run_dir, repo_root=repo_root)
        if args.output is not None
        else None
    )

    log_file = args.log_file
    if log_file is not None:
        log_file = resolve_output_path(log_file, run_dir=run_dir, repo_root=repo_root)
    elif not args.quiet:
        log_dir = run_dir / "logs"
        log_dir.mkdir(parents=True, exist_ok=True)
        log_file = log_dir / "convert.log"

    try:
        log = setup_logging(verbose=args.verbose, quiet=args.quiet, log_file=log_file)
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    log.info("Repo root: %s", repo_root)
    log.info("Run dir:   %s", run_dir)

    try:
        out = convert_run(
            run_dir,
            output=output,
            expnr=args.expnr,
            include_staggered=not args.no_staggered,
            include_fluxes=not args.no_fluxes,
            flux_at_cell_centers=not args.no_flux_centers,
            add_thermo=not args.no_thermo,
            overwrite=args.overwrite,
            require_complete=not args.allow_incomplete,
            consolidated=not args.no_consolidated,
            log=log,
            repo_root=repo_root,
        )
    except (FileNotFoundError, FileExistsError, RuntimeError, OSError, ValueError) as exc:
        log.error("%s", exc)
        return 1

    log.info("Wrote %s", out)
    print(f"Wrote {out}")
    if log_file is not None:
        print(f"Log: {log_file}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
