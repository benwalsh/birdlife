"""Fast, hardware-free checks for the renderer. Run from the frame/ dir:

    ../.venv/bin/python -m pytest connemara/test_smoke.py
"""
from connemara import render
from connemara.model import Detection, FrameState
from connemara.mockdata import sample_state, empty_state
from connemara.names import lookup
from connemara.theme import PANEL_W, PANEL_H
from datetime import datetime


def test_names_known_has_irish():
    n = lookup("Hirundo rustica")
    assert "Swallow" in n.en          # BirdNET en is "Barn Swallow"
    assert n.ga == "Fáinleog"


def test_birdnet_species_without_irish_has_no_ga():
    # A real BirdNET key (so English resolves) that BWI doesn't cover.
    n = lookup("Megascops kennicottii")
    assert n.en == "Western Screech-Owl"
    assert n.ga is None


def test_unknown_species_falls_back_to_sci():
    n = lookup("Foobarus imaginarius")
    assert n.en == "Foobarus imaginarius"
    assert n.ga is None


def test_state_orders_newest_first():
    a = Detection("A sp", datetime(2026, 6, 29, 10, 0))
    b = Detection("B sp", datetime(2026, 6, 29, 12, 0))
    state = FrameState.from_detections([a, b])
    assert state.now_showing is b
    assert state.today[0] is b and state.today[-1] is a


def test_renders_panel_sized_images():
    for mode in ("now", "today"):
        img = render.render(sample_state(), mode=mode)
        assert img.size == (PANEL_W, PANEL_H)
        assert render.dither_spectra6(img).size == (PANEL_W, PANEL_H)


def test_empty_state_renders():
    img = render.render(empty_state(), mode="now")
    assert img.size == (PANEL_W, PANEL_H)
