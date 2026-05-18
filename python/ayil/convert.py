"""CLI: merge fielddump NetCDF tiles and write ``data.zarr``."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from ayil.fielddump import merge_fielddump
from ayil.zarr_store import FIELDDUMP_CHUNKS_CENTER, write_dataset_zarr


def default_zarr_path(run_dir: Path) -> Path:
    return run_dir / "data.zarr"


def convert_run(
    run_dir: Path,
    *,
    output: Path | None = None,
    expnr: str = "001",
    chunks_center: tuple[int, int, int, int] = FIELDDUMP_CHUNKS_CENTER,
    include_staggered: bool = True,
    overwrite: bool = False,
) -> Path:
    run_dir = Path(run_dir)
    out = Path(output) if output else default_zarr_path(run_dir)

    if out.exists() and not overwrite:
        raise FileExistsError(
            f"{out} already exists; pass --overwrite to replace"
        )

    ds = merge_fielddump(
        run_dir, expnr=expnr, include_staggered=include_staggered
    )
    write_dataset_zarr(ds, out, mode="w", chunks_center=chunks_center)
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Merge DALES fielddump tiles into a single Zarr store."
    )
    parser.add_argument(
        "run_dir",
        type=Path,
        help="Run directory (e.g. runs/20200720)",
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
        "--overwrite",
        action="store_true",
        help="Replace existing Zarr store",
    )
    args = parser.parse_args(argv)

    try:
        out = convert_run(
            args.run_dir,
            output=args.output,
            expnr=args.expnr,
            include_staggered=not args.no_staggered,
            overwrite=args.overwrite,
        )
    except (FileNotFoundError, OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(f"Wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
