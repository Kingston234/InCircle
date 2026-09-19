from datetime import datetime, time, timedelta

from backend.app.geofencing import HysteresisState, advance_state, in_time_window

T0 = datetime(2026, 8, 19, 12, 0, 0)


def _st(inside: bool = False) -> HysteresisState:
    return HysteresisState(is_inside=inside)


def test_wejscie_po_n_probkach():
    st = _st(inside=False)
    assert advance_state(st, True, False, T0, confirm_samples=3) is None
    assert advance_state(st, True, False, T0, confirm_samples=3) is None
    assert advance_state(st, True, False, T0, confirm_samples=3) == "ENTER"
    assert st.is_inside is True


def test_oscylacja_w_pasie_histerezy_nie_zmienia_stanu():
    st = _st(inside=False)
    advance_state(st, True, False, T0, confirm_samples=3)
    advance_state(st, False, False, T0, confirm_samples=3)
    advance_state(st, True, False, T0, confirm_samples=3)
    assert advance_state(st, True, False, T0, confirm_samples=3) is None
    assert st.is_inside is False


def test_wyjscie_wymaga_probek_za_buforem():
    st = _st(inside=True)
    assert advance_state(st, False, False, T0, confirm_samples=1) is None
    assert advance_state(st, False, True, T0, confirm_samples=1) == "EXIT"
    assert st.is_inside is False


def test_dwell_opoznia_enter():
    st = _st(inside=False)
    advance_state(st, True, False, T0, 1, dwell_seconds=60)
    t1 = T0 + timedelta(seconds=59)
    assert advance_state(st, True, False, t1, 1, dwell_seconds=60) is None
    t2 = T0 + timedelta(seconds=61)
    assert advance_state(st, True, False, t2, 1, dwell_seconds=60) == "ENTER"


def test_okno_czasowe_zwykle_i_przez_polnoc():
    assert in_time_window(time(12, 0), time(8, 0), time(16, 0)) is True
    assert in_time_window(time(7, 59), time(8, 0), time(16, 0)) is False
    # okno 22:00-06:00 przechodzi przez polnoc
    assert in_time_window(time(23, 30), time(22, 0), time(6, 0)) is True
    assert in_time_window(time(3, 0), time(22, 0), time(6, 0)) is True
    assert in_time_window(time(12, 0), time(22, 0), time(6, 0)) is False


def test_brak_okna_oznacza_zawsze_aktywna():
    assert in_time_window(time(4, 44), None, None) is True
