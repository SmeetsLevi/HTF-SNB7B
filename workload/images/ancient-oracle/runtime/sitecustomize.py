"""
Runtime shims for the slim (Alpine) Python image, imported automatically
at start-up.

Configures stdout/stderr as UTF-8 and line-buffered so logs appear
immediately in `kubectl logs`. Does not monkey-patch JSON serialization.
"""

import sys


for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", line_buffering=True)
    except (AttributeError, ValueError):
        pass
