#!/usr/bin/env python3
"""Fail unless a fetched file is plausibly our schema.

curl -f fails on an HTTP error but not on a 200 with an empty or truncated
body, and oasdiff reads an empty file as every path having been removed, which
it rates breaking: the release would halt and file "Breaking API change
detected" over a bad proxy response. Check the bytes before anything
downstream trusts them.
"""

import json
import sys

MINIMUM_PATHS = 100

path = sys.argv[1]
with open(path) as f:
    paths = json.load(f).get("paths") or {}
if len(paths) < MINIMUM_PATHS:
    sys.exit(f"{path}: only {len(paths)} paths, expected at least {MINIMUM_PATHS}")
print(f"{path}: {len(paths)} paths")
