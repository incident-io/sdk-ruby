#!/usr/bin/env python3
"""Rewrite the committed schema into the one the generator reads.

openapi.json stays byte-for-byte what the API publishes, because the release
diffs it against the live schema and oasdiff needs the real thing. This writes
a second copy for the generator with three changes:

1. Enums become plain strings. The generator validates every enum in a model
   setter, and building a model from a response goes through the setters, so a
   value the server started sending raises ArgumentError for the *whole*
   response, on every already-installed copy of the gem. The release that knows
   the value is one those callers have not installed. Our API adds enum values
   as a backwards-compatible change, so this would break every client on a
   routine release. The generator's enumUnknownDefaultCase option is not a fix:
   it replaces the value with "unknown_default_open_api", so reading a resource
   and writing it back overwrites the field. As a string, the value survives.

   The known values move into the description, so the YARD docs still list
   them.

   The same validation guards request parameters (`allowable_values`), where it
   stops a caller on an old gem from sending a value the API accepts. Stripping
   the enum removes that too.

2. operationIds are snake-cased here rather than by the generator. Ours read
   "API Keys V1#Create", and the generator splits every capital, so it emits
   `a_pi_keys_v1_create`, `i_p_allowlists_v1_...` and `open_apiv3`. A method
   name is public API from the first release, so this has to be right before
   then. The rule below treats a run of capitals as one word; it agrees with
   the generator on the other 294 operations.

3. info.description is replaced with one line. The generator copies it into a
   header comment at the top of every file, and it is 7.7KB of prose written
   for the API docs: 1,200 copies came to 9MB of a 21MB lib/.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

DESCRIPTION = "Ruby client for the incident.io API."

# Floor, not a pin: exists to catch the walk silently matching nothing, not to
# fix the schema's shape. There were 325 at the time of writing.
ENUM_FLOOR = 200


def strip_enums(node: object) -> int:
    """Remove every enum in place, returning how many."""
    count = 0
    if isinstance(node, dict):
        values = node.get("enum")
        if isinstance(values, list):
            del node["enum"]
            count += 1
            known = ", ".join(f"`{value}`" for value in values)
            description = node.get("description", "").rstrip()
            node["description"] = f"{description}\n\nKnown values: {known}".lstrip()
        for value in node.values():
            count += strip_enums(value)
    elif isinstance(node, list):
        for value in node:
            count += strip_enums(value)
    return count


def snake_case(operation_id: str) -> str:
    """"API Keys V1#Create" -> "api_keys_v1_create"."""
    words = re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1_\2", operation_id)  # APIKeys -> API_Keys
    words = re.sub(r"([A-Z]+)([A-Z]\d)", r"\1_\2", words)  # APIV3 -> API_V3
    words = re.sub(r"([a-z\d])([A-Z])", r"\1_\2", words)  # ShowIP -> Show_IP
    return re.sub(r"[^A-Za-z0-9]+", "_", words).strip("_").lower()


def rename_operations(spec: dict) -> int:
    renamed = 0
    for item in (spec.get("paths") or {}).values():
        for operation in item.values():
            if isinstance(operation, dict) and "operationId" in operation:
                operation["operationId"] = snake_case(operation["operationId"])
                renamed += 1
    return renamed


def main(source: str, destination: str) -> int:
    spec = json.loads(Path(source).read_text())

    spec.setdefault("info", {})["description"] = DESCRIPTION

    print(f"Renamed {rename_operations(spec)} operations")

    stripped = strip_enums(spec)
    print(f"Stripped {stripped} enums")
    if stripped < ENUM_FLOOR:
        print(
            f"Expected at least {ENUM_FLOOR} enums. Either the schema changed "
            "shape or this pass stopped matching; check before releasing.",
            file=sys.stderr,
        )
        return 1

    Path(destination).parent.mkdir(parents=True, exist_ok=True)
    Path(destination).write_text(json.dumps(spec, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <openapi.json> <prepared.json>", file=sys.stderr)
        raise SystemExit(2)
    raise SystemExit(main(sys.argv[1], sys.argv[2]))
