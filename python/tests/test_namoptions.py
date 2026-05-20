"""Tests for namoptions parsing."""

from __future__ import annotations

from pathlib import Path

import pytest

from ayil.namoptions import parse_namoptions_physics


def test_parse_physics(tmp_path: Path) -> None:
    nam = tmp_path / "namoptions"
    nam.write_text(
        "&physics\n    ps = 100805.48\n    thls = 278.61\n/\n",
        encoding="utf-8",
    )
    p = parse_namoptions_physics(nam)
    assert p.ps == pytest.approx(100805.48)
    assert p.thls == pytest.approx(278.61)


def test_missing_ps_raises(tmp_path: Path) -> None:
    nam = tmp_path / "namoptions"
    nam.write_text("&physics\n    thls = 278.61\n/\n", encoding="utf-8")
    with pytest.raises(ValueError, match="ps"):
        parse_namoptions_physics(nam)
