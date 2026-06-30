"""Connemara bespoke e-ink renderer.

A bilingual (Irish + English) display for the AvianVisitors build at
Connemara. Draws cards directly with Pillow for the 7.3" Inky Impression
(Spectra-6, 800x480), rather than mirroring the web collage.

Everything here is desktop-testable: render to a dithered PNG with
``python -m connemara.preview`` (run from the ``frame/`` directory). No Pi or
Inky hardware is needed until the final on-glass tuning pass.
"""
