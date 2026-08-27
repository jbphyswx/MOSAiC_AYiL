"""Scalar rename maps match SB3 microphysics indices."""

from __future__ import annotations

from ayil.scalar_names import AYiL_SB3_SCALAR_NAMES, rename_scalar_variables


def test_sv001_is_rain_number() -> None:
    assert rename_scalar_variables("sv001") == "n_rain"
    assert rename_scalar_variables("sv002") == "q_rain"
    assert len(AYiL_SB3_SCALAR_NAMES) == 12
