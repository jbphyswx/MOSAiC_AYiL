"""Map DALES fielddump ``svNNN`` indices to physical names (SB3 bulk microphysics, imicro=11)."""

from __future__ import annotations

# Order matches modmicrodata3.f90 indices in_hr=1 … iq_hg=12 for nsv=12 / imicro=11.
AYIL_SB3_SCALAR_NAMES: dict[str, str] = {
    "sv001": "n_rain",
    "sv002": "q_rain",
    "sv003": "n_cloud_liquid",
    "sv004": "n_inp",
    "sv005": "q_cloud_liquid",
    "sv006": "n_ccn",
    "sv007": "n_ice",
    "sv008": "q_ice",
    "sv009": "n_snow",
    "sv010": "q_snow",
    "sv011": "n_graupel",
    "sv012": "q_graupel",
}

AYIL_SB3_SCALAR_LONG_NAMES: dict[str, str] = {
    "n_rain": "rain drop number concentration",
    "q_rain": "rain specific mass mixing ratio",
    "n_cloud_liquid": "cloud droplet number concentration",
    "n_inp": "ice-nucleating particle number concentration",
    "q_cloud_liquid": "cloud liquid water mixing ratio",
    "n_ccn": "cloud condensation nuclei number concentration",
    "n_ice": "ice crystal number concentration",
    "q_ice": "ice crystal mass mixing ratio",
    "n_snow": "snow number concentration",
    "q_snow": "snow mass mixing ratio",
    "n_graupel": "graupel number concentration",
    "q_graupel": "graupel mass mixing ratio",
}


def rename_scalar_variables(ds_name: str) -> str:
    """Return physical name for ``sv001``-style ``ds_name``, or pass through."""
    if ds_name in AYIL_SB3_SCALAR_NAMES:
        return AYIL_SB3_SCALAR_NAMES[ds_name]
    return ds_name
