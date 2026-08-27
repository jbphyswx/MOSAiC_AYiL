"""Parse selected keys from DALES ``namoptions`` files."""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

# DALES namelists end with ``/`` (next ``&`` starts another block).
_PHYSICS_BLOCK = re.compile(r"&physics\s*(.*?)(?:/|\Z)", re.IGNORECASE | re.DOTALL)
_PS = re.compile(r"^\s*ps\s*=\s*([0-9.eE+\-]+)", re.IGNORECASE | re.MULTILINE)
_THLS = re.compile(r"^\s*thls\s*=\s*([0-9.eE+\-]+)", re.IGNORECASE | re.MULTILINE)


@dataclass(frozen=True)
class NamoptionsPhysics:
    """Surface pressure and reference liquid potential temperature from ``&physics``."""

    ps: float
    thls: float


def parse_namoptions_physics(path: Path | str) -> NamoptionsPhysics:
    """
    Read ``ps`` and ``thls`` from the ``&physics`` namelist block.

    Raises ``ValueError`` if either key is missing.
    """
    text = Path(path).read_text(encoding="utf-8", errors="replace")
    block = _PHYSICS_BLOCK.search(text)
    if block is None:
        raise ValueError(f"no &physics block in {path}")
    body = block.group(1)
    m_ps = _PS.search(body)
    m_thls = _THLS.search(body)
    if m_ps is None or m_thls is None:
        missing = [k for k, m in (("ps", m_ps), ("thls", m_thls)) if m is None]
        raise ValueError(f"missing {', '.join(missing)} in &physics ({path})")
    return NamoptionsPhysics(ps=float(m_ps.group(1)), thls=float(m_thls.group(1)))
