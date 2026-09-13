# Copyright 2026 Trieflow LLC. MIT.
"""Read-only, bounded source status checkpoint; never qualification evidence."""
import argparse
from pathlib import Path
from export_store import observe_source_status

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--phase',required=True,choices=('after-build','after-installation'))
    args=parser.parse_args()
    observe_source_status(Path(__file__).resolve().parents[1],args.phase)
