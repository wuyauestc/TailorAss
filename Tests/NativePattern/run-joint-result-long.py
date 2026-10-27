#!/usr/bin/env python3
"""Explicit long-run entry; zero exit is not garment acceptance.

Use --package-source with an approved frozen package. Runs from the complete
native initial state, stopping at the first rejected step or first stable flag;
only successful independent final validation writes validated output artifacts.
"""
from pathlib import Path
import subprocess,sys
if any(x=='--mode' or x.startswith('--mode=') for x in sys.argv[1:]):raise SystemExit('This entry fixes --mode simulate; use run-joint-result.py for controls')
raise SystemExit(subprocess.call([sys.executable,str(Path(__file__).with_name('run-joint-result.py')),'--mode','simulate',*sys.argv[1:]]))
