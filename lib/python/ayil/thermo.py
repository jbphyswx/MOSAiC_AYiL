"""
Offline moist thermodynamics for merged fielddump datasets.

Pressure on full levels follows DALES ``fromztop`` (``modthermodynamics.f90``) using
domain-mean ``thl``, ``qt``, and ``ql`` profiles. Temperature uses the same relation
as DALES buoyancy / post-``icethermo0`` diagnostics:

    T = exner * thl + (L_v / c_p) * ql

with ``exner = (presf / p_ref)^(R_d / c_p)`` and ``p_ref = pref0`` (100 hPa).
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import xarray as xr

from ayil.namoptions import NamoptionsPhysics, parse_namoptions_physics
from ayil.paths import find_repo_root

# DALES modglobal.f90
GRAV = 9.81
RD = 287.04
RV = 461.5
CP = 1004.0
RLV = 2.53e6
PREF0 = 1.0e5
RD_CP = RD / CP


@dataclass(frozen=True)
class DalesThermoConstants:
    grav: float = GRAV
    rd: float = RD
    rv: float = RV
    cp: float = CP
    rlv: float = RLV
    pref0: float = PREF0

    @property
    def rlv_over_cp(self) -> float:
        return self.rlv / self.cp


def find_namoptions(run_dir: Path | str, *, repo_root: Path | None = None) -> Path:
    """``<run_dir>/namoptions`` or ``ayil_config_input_results/YYYYMMDD/namoptions``."""
    run_dir = Path(run_dir)
    local = run_dir / "namoptions"
    if local.is_file():
        return local.resolve()
    name = run_dir.name
    if len(name) == 8 and name.isdigit():
        root = repo_root if repo_root is not None else find_repo_root()
        dated = root / "ayil_config_input_results" / name / "namoptions"
        if dated.is_file():
            return dated.resolve()
    raise FileNotFoundError(
        f"namoptions not found in {run_dir} or ayil_config_input_results/{name}/"
    )


def find_prof_inp(run_dir: Path | str, *, expnr: str = "001", repo_root: Path | None = None) -> Path | None:
    """Return ``prof.inp.<expnr>`` beside the run or under the dated input bundle."""
    run_dir = Path(run_dir)
    for candidate in (
        run_dir / f"prof.inp.{expnr}",
        run_dir / f"prof.inp.{int(expnr):03d}",
    ):
        if candidate.is_file():
            return candidate.resolve()
    name = run_dir.name
    if len(name) == 8 and name.isdigit():
        root = repo_root if repo_root is not None else find_repo_root()
        dated = root / "ayil_config_input_results" / name / f"prof.inp.{expnr}"
        if dated.is_file():
            return dated.resolve()
    return None


def read_prof_inp_zf(path: Path | str, *, n_levels: int | None = None) -> np.ndarray:
    """
    Read full-level heights ``zf`` (m) from ``prof.inp.*`` (first numeric column).

    Skips comment lines. Optionally truncate to ``n_levels`` (fielddump ``khigh``).
    """
    heights: list[float] = []
    for line in Path(path).read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if not parts:
            continue
        try:
            heights.append(float(parts[0]))
        except ValueError:
            continue
    if not heights:
        raise ValueError(f"no height levels in {path}")
    zf = np.asarray(heights, dtype=np.float64)
    if n_levels is not None:
        zf = zf[:n_levels]
    return zf


def dales_vertical_metrics(zf: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """
    Build ``dzf``, ``dzh``, and extended ``zf`` on full levels (DALES ``initglobal``).

    ``zf`` input has length ``kmax`` (full-level heights from ``prof.inp``).
    Returns ``zf_out`` length ``k1 = kmax + 1`` for the top interface.
    """
    zf_in = np.asarray(zf, dtype=np.float64)
    kmax = zf_in.size
    if kmax < 1:
        raise ValueError("zf must have at least one level")

    zh = np.zeros(kmax + 1, dtype=np.float64)
    for k in range(kmax):
        zh[k + 1] = zh[k] + 2.0 * (zf_in[k] - zh[k])

    zf_out = np.empty(kmax + 1, dtype=np.float64)
    zf_out[:kmax] = zf_in
    zf_out[kmax] = zf_in[kmax - 1] + 2.0 * (zh[kmax] - zf_in[kmax - 1])

    dzf = np.empty(kmax + 1, dtype=np.float64)
    for k in range(kmax):
        dzf[k] = zh[k + 1] - zh[k]
    dzf[kmax] = dzf[kmax - 1]

    dzh = np.empty(kmax + 1, dtype=np.float64)
    dzh[0] = 2.0 * zf_out[0]
    for k in range(1, kmax + 1):
        dzh[k] = zf_out[k] - zf_out[k - 1]

    return zf_out, dzf, dzh


def presf_fromztop(
    ps: float,
    thl_av: np.ndarray,
    qt_av: np.ndarray,
    ql_av: np.ndarray,
    zf: np.ndarray,
    *,
    constants: DalesThermoConstants | None = None,
) -> np.ndarray:
    """
    Hydrostatic ``presf`` on full levels (Pa), port of DALES ``fromztop`` (``modthermodynamics.f90``).

    ``thl_av``, ``qt_av``, ``ql_av`` are domain-mean profiles length ``k1`` (number of full levels).
    ``zf`` is the DALES full-level height array (length ``kmax`` from ``prof.inp``); metrics are
  built internally.
    """
    c = constants or DalesThermoConstants()
    thl_av = np.asarray(thl_av, dtype=np.float64)
    qt_av = np.asarray(qt_av, dtype=np.float64)
    ql_av = np.asarray(ql_av, dtype=np.float64)
    k1 = thl_av.size
    if qt_av.shape != (k1,) or ql_av.shape != (k1,):
        raise ValueError("thl_av, qt_av, ql_av must have the same length")

    zf_full, dzf, dzh = dales_vertical_metrics(zf)
    # zf_full length k1; presf on full levels 0..k1-1 (Fortran 1..k1)

    rdocp = c.rd / c.cp
    presf = np.empty(k1, dtype=np.float64)
    thvh = np.empty(k1, dtype=np.float64)
    thetah = np.empty(k1, dtype=np.float64)
    qth = np.empty(k1, dtype=np.float64)
    qlh = np.empty(k1, dtype=np.float64)

    thvh[0] = thl_av[0] * (1.0 + (c.rv / c.rd - 1.0) * qt_av[0] - c.rv / c.rd * ql_av[0])
    presf[0] = ps**rdocp - c.grav * (c.pref0**rdocp) * zf_full[0] / (c.cp * thvh[0])
    presf[0] = presf[0] ** (1.0 / rdocp)

    for k in range(1, k1):
        thetah[k] = (thl_av[k] * dzf[k - 1] + thl_av[k - 1] * dzf[k]) / (2.0 * dzh[k])
        qth[k] = (qt_av[k] * dzf[k - 1] + qt_av[k - 1] * dzf[k]) / (2.0 * dzh[k])
        qlh[k] = (ql_av[k] * dzf[k - 1] + ql_av[k - 1] * dzf[k]) / (2.0 * dzh[k])
        thvh[k] = thetah[k] * (1.0 + (c.rv / c.rd - 1.0) * qth[k] - c.rv / c.rd * qlh[k])
        presf[k] = presf[k - 1] ** rdocp - c.grav * (c.pref0**rdocp) * dzh[k] / (c.cp * thvh[k])
        presf[k] = presf[k] ** (1.0 / rdocp)

    return presf


def exner_from_presf(presf: np.ndarray, *, pref0: float = PREF0) -> np.ndarray:
    """Exner function ``(presf / pref0)^(R_d / c_p)``."""
    presf = np.asarray(presf, dtype=np.float64)
    return (presf / pref0) ** RD_CP


def temperature_from_thl_ql(
    thl: xr.DataArray,
    ql: xr.DataArray,
    exner: np.ndarray,
    *,
    constants: DalesThermoConstants | None = None,
) -> xr.DataArray:
    """``T = exner(z) * thl + (L_v / c_p) * ql`` with ``exner`` broadcast along horizontal dims."""
    c = constants or DalesThermoConstants()
    exner_da = xr.DataArray(
        exner.astype(np.float32),
        dims=("z",),
        coords={"z": thl.coords["z"]},
        attrs={
            "long_name": "Exner function",
            "standard_name": "dimensionless",
            "formula": f"(presf / {c.pref0:g})^({RD_CP:.6f})",
        },
    )
    temp = (exner_da * thl + c.rlv_over_cp * ql).astype(np.float32)
    return temp.transpose(*thl.dims)


def column_means_at_first_time(
    ds: xr.Dataset,
    *,
    z_dim: str = "z",
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Domain-mean ``thl``, ``qt``, ``ql`` on ``z`` using the first time index."""
    horiz = [d for d in ("x", "y") if d in ds["thl"].dims]
    sel = ds.isel(time=0)
    thl_av = sel["thl"].mean(dim=horiz).values.astype(np.float64)
    qt_av = sel["qt"].mean(dim=horiz).values.astype(np.float64)
    ql_av = sel["ql"].mean(dim=horiz).values.astype(np.float64)
    return thl_av, qt_av, ql_av


def _squeeze_horiz_uniform_profile(da: xr.DataArray, horiz: tuple[str, ...] = ("x", "y")) -> xr.DataArray:
    """If ``da`` is constant over horizontal dims, return the 1D vertical profile."""
    present = [d for d in horiz if d in da.dims]
    if not present:
        return da
    spread = float((da.max(dim=present) - da.min(dim=present)).max())
    if spread > 1.0e-3:
        return da
    return da.mean(dim=present)


def add_thermo_derivatives(
    ds: xr.Dataset,
    *,
    ps: float,
    zf: np.ndarray | None = None,
    prof_inp: Path | str | None = None,
    constants: DalesThermoConstants | None = None,
    log: logging.Logger | None = None,
    prefer_fielddump: bool = True,
) -> xr.Dataset:
    """
    Add ``pressure`` (z), ``exner`` (z), and ``temperature`` (time, z, y, x) to ``ds``.

    When ``prefer_fielddump`` is true and the merged dataset already contains model
    ``pressure`` / ``exner`` / ``temperature`` from ``modfielddump``, those are kept
    (horizontal slabs collapsed to ``(z,)`` for pressure and exner). Otherwise uses
  offline ``fromztop`` with domain-mean ``thl`` / ``qt`` / ``ql`` at ``time=0``.
    """
    log = log or logging.getLogger("ayil")
    c = constants or DalesThermoConstants()

    if prefer_fielddump and all(v in ds for v in ("pressure", "exner", "temperature")):
        log.info("Using pressure, exner, temperature from fielddump (model tmp0 / presf)")
        out = ds.copy()
        out["pressure"] = _squeeze_horiz_uniform_profile(ds["pressure"]).assign_attrs(
            {
                "long_name": "air pressure",
                "standard_name": "air_pressure",
                "units": "Pa",
                "source": "DALES fielddump presf",
            }
        )
        out["exner"] = _squeeze_horiz_uniform_profile(ds["exner"]).assign_attrs(
            {
                "long_name": "Exner function",
                "units": "1",
                "source": "DALES fielddump exnf",
            }
        )
        out["temperature"] = ds["temperature"].assign_attrs(
            {
                "long_name": "air temperature",
                "standard_name": "air_temperature",
                "units": "K",
                "source": "DALES fielddump tmp0",
            }
        )
        out.attrs["thermo_pressure_source"] = "DALES fielddump presf"
        out.attrs["thermo_temperature_source"] = "DALES fielddump tmp0"
        return out
    missing = [v for v in ("thl", "qt", "ql") if v not in ds]
    if missing:
        raise ValueError(f"dataset missing variables for thermo: {missing}")
    if "z" not in ds.coords:
        raise ValueError("dataset missing coordinate 'z'")

    n_z = int(ds.sizes["z"])
    if zf is None:
        if prof_inp is None:
            raise ValueError("zf or prof_inp required for vertical grid")
        zf = read_prof_inp_zf(prof_inp, n_levels=n_z)
    else:
        zf = np.asarray(zf, dtype=np.float64)
        if zf.size != n_z:
            raise ValueError(f"zf length {zf.size} != dataset z size {n_z}")

    thl_av, qt_av, ql_av = column_means_at_first_time(ds)
    presf = presf_fromztop(ps, thl_av, qt_av, ql_av, zf, constants=c)
    exner = exner_from_presf(presf, pref0=c.pref0)

    log.info(
        "Thermo: presf surface=%.1f Pa, top=%.1f Pa (ps=%.1f Pa, n_z=%d)",
        float(presf[0]),
        float(presf[-1]),
        ps,
        n_z,
    )

    temp = temperature_from_thl_ql(ds["thl"], ds["ql"], exner, constants=c)

    out = ds.copy()
    out["pressure"] = xr.DataArray(
        presf.astype(np.float32),
        dims=("z",),
        coords={"z": ds.coords["z"]},
        attrs={
            "long_name": "air pressure",
            "standard_name": "air_pressure",
            "units": "Pa",
            "comment": "Hydrostatic presf on full levels (DALES fromztop); domain-mean thl/qt/ql at t[0].",
        },
    )
    out["exner"] = xr.DataArray(
        exner.astype(np.float32),
        dims=("z",),
        coords={"z": ds.coords["z"]},
        attrs={
            "long_name": "Exner function",
            "units": "1",
            "formula": f"(pressure / {c.pref0:g})^{RD_CP:.6f}",
        },
    )
    out["temperature"] = temp.assign_attrs(
        {
            "long_name": "air temperature",
            "standard_name": "air_temperature",
            "units": "K",
            "formula": "exner * thl + (L_v/c_p) * ql",
        }
    )
    out.attrs["thermo_pressure_source"] = "DALES fromztop"
    out.attrs["thermo_temperature_formula"] = "exner * thl + (L_v/c_p) * ql"
    return out


def add_thermo_derivatives_for_run(
    ds: xr.Dataset,
    run_dir: Path | str,
    *,
    expnr: str = "001",
    repo_root: Path | None = None,
    log: logging.Logger | None = None,
) -> xr.Dataset:
    """Resolve ``namoptions`` / ``prof.inp`` for ``run_dir`` and call :func:`add_thermo_derivatives`."""
    run_dir = Path(run_dir)
    nam = find_namoptions(run_dir, repo_root=repo_root)
    physics = parse_namoptions_physics(nam)
    prof = find_prof_inp(run_dir, expnr=expnr, repo_root=repo_root)
    if prof is None:
        raise FileNotFoundError(
            f"prof.inp.{expnr} not found for run {run_dir} (needed for DALES zf grid)"
        )
    return add_thermo_derivatives(
        ds,
        ps=physics.ps,
        prof_inp=prof,
        log=log,
    )
