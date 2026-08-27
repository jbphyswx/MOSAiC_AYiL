"""CLI: merge fielddump NetCDF tiles and write ``data.zarr``."""

from __future__ import annotations

import argparse
import logging
import sys
import time
from pathlib import Path

from ayil.fielddump import fielddump_has_snapshots, find_fielddump_tiles, merge_fielddump
from ayil.logging_utils import human_bytes, setup_logging
from ayil.paths import find_repo_root, resolve_output_path, resolve_run_dir
from ayil.thermo import add_thermo_derivatives_for_run
from zarr.codecs import BloscCodec

from ayil.convert_stamps import fielddump_newer_than_zarr, fielddump_source_stamp, stamp_to_attrs
from ayil.zarr_store import FIELDDUMP_CHUNKS_CENTER, write_dataset_zarr

AYiL_COMPLETE = ".ayil_complete"
AYiL_RUNNING = ".ayil_running"


def _check_run_ready(
    run_dir: Path,
    *,
    require_complete: bool,
    allow_running: bool,
    log: logging.Logger,
) -> None:
    complete = run_dir / AYiL_COMPLETE
    running = run_dir / AYiL_RUNNING

    if running.exists() and not complete.exists() and not allow_running:
        raise RuntimeError(
            f"{run_dir} is still marked running ({AYiL_RUNNING}). "
            "Wait for DALES to finish, pass --allow-running, or use batch mode (skips active runs)."
        )

    if require_complete and not complete.exists():
        raise RuntimeError(
            f"{run_dir} has no {AYiL_COMPLETE}. "
            "Partial fielddump is converted by default; use --complete-only to require the marker."
        )

    if complete.exists():
        log.info("Run status: %s present", AYiL_COMPLETE)
    elif not require_complete:
        log.warning("Run status: no %s (converting available fielddump)", AYiL_COMPLETE)


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
    require_complete: bool = False,
    allow_running: bool = False,
    update_if_stale: bool = True,
    skip_if_current: bool = False,
    consolidated: bool = True,
    codec: BloscCodec | None = None,
    log: logging.Logger | None = None,
    repo_root: Path | None = None,
) -> Path:
    """
    Merge fielddump tiles under ``run_dir`` and write a Zarr store.

    By default partial days are allowed. If ``data.zarr`` exists and fielddump has
    more time steps or newer tiles, the store is rewritten (full merge, not time-append).
    """
    log = log or logging.getLogger("ayil")
    run_dir = Path(run_dir).resolve()
    out = Path(output).resolve() if output else (run_dir / "data.zarr")

    if not run_dir.is_dir():
        raise FileNotFoundError(f"run directory not found: {run_dir}")

    if not find_fielddump_tiles(run_dir, expnr=expnr):
        raise FileNotFoundError(f"no fielddump tiles in {run_dir}")

    if not fielddump_has_snapshots(run_dir, expnr=expnr):
        raise ValueError(
            f"fielddump tiles in {run_dir} have no time snapshots (time size 0). "
            "The run directory is not empty, but DALES never wrote fielddump output "
            "(failed run, incomplete sync, or simulation still at t=0)."
        )

    _check_run_ready(
        run_dir,
        require_complete=require_complete,
        allow_running=allow_running,
        log=log,
    )

    if out.exists() and not overwrite:
        if skip_if_current and not fielddump_newer_than_zarr(run_dir, out, expnr=expnr):
            log.info("Skip %s (data.zarr matches fielddump)", out)
            return out
        if update_if_stale and fielddump_newer_than_zarr(run_dir, out, expnr=expnr):
            log.info("Refresh %s (fielddump newer than existing Zarr)", out)
            overwrite = True
        elif not update_if_stale:
            raise FileExistsError(
                f"{out} already exists; pass --overwrite or omit --no-update"
            )

    stamp = fielddump_source_stamp(run_dir, expnr=expnr)

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

    ds.attrs.update(stamp_to_attrs(stamp))

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


def _convert_kwargs_from_args(args: argparse.Namespace) -> dict:
    return {
        "expnr": args.expnr,
        "include_staggered": not args.no_staggered,
        "include_fluxes": not args.no_fluxes,
        "flux_at_cell_centers": not args.no_flux_centers,
        "add_thermo": not args.no_thermo,
        "overwrite": args.overwrite,
        "require_complete": args.complete_only,
        "consolidated": not args.no_consolidated,
        "update_if_stale": not args.no_update,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Merge DALES fielddump tiles into Zarr stores under runs/YYYYMMDD/data.zarr.",
        epilog=(
            "With no run directories, converts every runs/YYYYMMDD that has fielddump tiles:\n"
            "  python -m ayil.convert\n"
            "  ./scripts/convert_to_zarr.sh\n"
            "Skips days still running; skips up-to-date data.zarr; rewrites when fielddump grew."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "run_dirs",
        nargs="*",
        type=Path,
        help="Run dirs (e.g. runs/20200720). Default: all under runs/ with fielddump.",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=None,
        help="Output Zarr path (single-run only; default <run_dir>/data.zarr)",
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
        help="Replace Zarr even when fielddump has not changed",
    )
    parser.add_argument(
        "--no-update",
        action="store_true",
        help="Do not refresh existing data.zarr when fielddump grew (still create missing)",
    )
    parser.add_argument(
        "--complete-only",
        action="store_true",
        help=f"Only convert runs with {AYiL_COMPLETE}",
    )
    parser.add_argument(
        "--allow-running",
        action="store_true",
        help=f"Allow convert while {AYiL_RUNNING} is set (batch mode skips these by default)",
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
        help="Log file (single-run: runs/YYYYMMDD/logs/convert.log; batch: runs/convert_batch.log)",
    )
    args = parser.parse_args(argv)

    repo_root = find_repo_root()
    convert_kw = _convert_kwargs_from_args(args)

    if len(args.run_dirs) > 1 and args.output is not None:
        print("ERROR: --output is only valid for a single run directory", file=sys.stderr)
        return 1

    if len(args.run_dirs) == 0:
        from ayil.convert_batch import convert_runs_batch, discover_run_dirs

        runs_root = repo_root / "runs"
        run_dirs = discover_run_dirs(runs_root)
        if not run_dirs:
            print(f"No runs with fielddump under {runs_root}", file=sys.stderr)
            return 1

        log_file = args.log_file
        if log_file is None and not args.quiet:
            log_file = runs_root / "convert_batch.log"
        try:
            log = setup_logging(verbose=args.verbose, quiet=args.quiet, log_file=log_file)
        except ValueError as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            return 1

        log.info("Batch convert: %d run(s) under %s", len(run_dirs), runs_root)
        results = convert_runs_batch(
            run_dirs,
            repo_root=repo_root,
            log=log,
            skip_active=not args.allow_running,
            **convert_kw,
        )
        n_ok = len(results["converted"]) + len(results["updated"])
        n_fail = len(results["failed"])
        print(
            f"Done: {n_ok} written ({len(results['converted'])} new, "
            f"{len(results['updated'])} refreshed), "
            f"{len(results['skipped'])} up-to-date, "
            f"{len(results['skipped_active'])} running, "
            f"{len(results['skipped_no_tiles'])} no tiles, "
            f"{len(results['skipped_no_snapshots'])} no snapshots, "
            f"{n_fail} failed"
        )
        if log_file is not None:
            print(f"Log: {log_file}", file=sys.stderr)
        return 1 if n_fail else 0

    # Single run
    run_dir = resolve_run_dir(args.run_dirs[0], repo_root=repo_root)
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
            allow_running=args.allow_running,
            repo_root=repo_root,
            log=log,
            **convert_kw,
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
