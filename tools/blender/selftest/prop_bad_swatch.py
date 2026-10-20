"""Negative fixture: an unknown swatch name must stop the recipe with a non-zero exit code."""
import pw

pw.begin("prop_bad", "prop")
pw.box("Crate", (1, 1, 1), (0, 0, 0.5), "not_a_swatch")
