#!/usr/bin/env python3
"""Repair the generated client where the generator will not.

scripts/prepare_spec.py handles what can be fixed in the schema (enums, the
header prose). This handles what can only be fixed in the output:

1. lib/incident_io.rb loads the hand-written files: errors.rb (an error
   subclass per status, with `request_id`) and deprecation.rb.

2. Deprecated endpoints are marked. The generator ignores the schema's
   `deprecated` flag and copies only its prose. This adds a YARD @deprecated
   tag to both entry points and a runtime warning from
   lib/incident_io/deprecation.rb, which Ruby shows when deprecation warnings
   are on. sdk-go and sdk-python fill the same gap.

3. `require 'cgi/escape'`. Every path parameter goes through CGI.escape, and
   the generated code never requires it: today something in Faraday's
   dependency tree happens to load it first. Ruby 4.0 dropped the rest of
   `cgi` from the default gems and kept only cgi/escape, so this is the one
   require that stays valid on every Ruby we support.

4. Raw NUL bytes are escaped. core declares a pattern as the Go string
   "^[^\\x00]*$", which holds a literal NUL character, and the generator copies
   it into a Regexp literal byte for byte. Ruby parses it, but git and grep
   treat the whole file as binary, so its diffs vanish from every release
   commit. The root fix is a raw string in core
   (server/api/design/helpers/helpers.go); delete this once that lands.

Each fix names the text it replaces and fails if that text is missing, so an
upstream generator change surfaces as a failed release rather than a silently
skipped patch. A post-generation pass rather than a forked template, because a
fork fails silently: openapi-generator opts out of mustache's
fail-on-missing-key, so when upstream renames a variable a forked template
still renders and quietly drops the branch. See the template-drift make
target, which watches the templates these anchors come from.

Report anything fixed here upstream, and delete it when it lands.
"""

from __future__ import annotations

import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

METHODS = ("get", "post", "put", "patch", "delete")


@dataclass(frozen=True)
class Fix:
    """A single replacement in one file."""

    name: str
    path: str
    old: str
    new: str


FIXES = (
    Fix(
        name="lib/incident_io.rb requires cgi/escape and the hand-written files",
        path="incident_io.rb",
        old="require 'incident_io/api_error'\n",
        new=(
            "require 'cgi/escape'\n"
            "require 'incident_io/api_error'\n"
            "require 'incident_io/errors'\n"
            "require 'incident_io/deprecation'\n"
        ),
    ),
)


def apply(fix: Fix, lib: Path) -> bool:
    """Runs on fresh generator output only: make generate regenerates every
    file this touches first."""
    file = lib / fix.path
    source = file.read_text()
    if fix.old not in source:
        return False
    file.write_text(source.replace(fix.old, fix.new, 1))
    return True


def escape_nul_bytes(lib: Path) -> int:
    """Not a Fix: whether there is anything to escape depends on the schema,
    so matching nothing is not a failure."""
    escaped = 0
    for file in sorted(lib.rglob("*.rb")):
        raw = file.read_bytes()
        if b"\x00" in raw:
            escaped += raw.count(b"\x00")
            file.write_bytes(raw.replace(b"\x00", b"\\x00"))
    return escaped


def path_shape(path: str) -> str:
    """A path with its parameter names erased.

    The schema may call a parameter `followUpId` where the generated code says
    `follow_up_id`. Comparing only the shape avoids re-implementing the
    generator's naming rules. Two operations cannot differ by parameter name
    alone, so nothing is lost.
    """
    return re.sub(r"\{[^}]+\}", "{}", path)


def deprecated_operations(spec: dict) -> set[tuple[str, str]]:
    found = set()
    for path, item in (spec.get("paths") or {}).items():
        for method, operation in item.items():
            if method in METHODS and isinstance(operation, dict) and operation.get("deprecated"):
                found.add((method.upper(), path_shape(path)))
    return found


# One generated method: its name, then (lazily) the path and verb it calls.
# Anchored on the _with_http_info method because the plain one only delegates.
OPERATION = re.compile(
    r"^    def (?P<name>\w+)_with_http_info\(.*?"
    r"local_var_path = '(?P<path>[^']+)'.*?"
    r"@api_client\.call_api\(:(?P<verb>[A-Z]+),",
    re.M | re.S,
)

DEPRECATED_TAG = "    # @deprecated {endpoint} is deprecated and will be removed.\n"
WARNING_CALL = '      IncidentIo::Deprecation.warn("{endpoint}")\n'


def mark(source: str, name: str, endpoint: str) -> str:
    """Tag both entry points and warn from the one both go through."""
    tag = DEPRECATED_TAG.format(endpoint=endpoint)
    for signature in (f"    def {name}(", f"    def {name}_with_http_info("):
        at = source.index(signature)
        source = source[:at] + tag + source[at:]

    # The first line of the body, so the warning fires before any validation
    # can raise.
    header = re.search(rf"^    def {name}_with_http_info\(.*\n", source, re.M)
    call = WARNING_CALL.format(endpoint=endpoint)
    return source[: header.end()] + call + source[header.end():]


def mark_deprecated(lib: Path, spec_path: Path) -> tuple[int, int]:
    spec = json.loads(spec_path.read_text())
    wanted = deprecated_operations(spec)
    marked: set[tuple[str, str]] = set()

    for file in sorted((lib / "incident_io" / "api").glob("*.rb")):
        source = file.read_text()
        updated = source
        for match in OPERATION.finditer(source):
            operation = (match["verb"], path_shape(match["path"]))
            if operation not in wanted:
                continue
            endpoint = f"{match['verb']} {match['path']}"
            updated = mark(updated, match["name"], endpoint)
            marked.add(operation)
        if updated != source:
            file.write_text(updated)

    for verb, path in sorted(wanted - marked):
        print(f"  unmatched deprecated operation: {verb} {path}", file=sys.stderr)
    return len(marked), len(wanted)


def main(lib_path: str, spec_path: str) -> int:
    lib = Path(lib_path)
    failed = False

    for fix in FIXES:
        if apply(fix, lib):
            print(f"Fixed: {fix.name}")
        else:
            print(f"  no match: {fix.name}", file=sys.stderr)
            failed = True

    escaped = escape_nul_bytes(lib)
    if escaped:
        print(f"Fixed: escaped {escaped} NUL byte(s)")

    marked, wanted = mark_deprecated(lib, Path(spec_path))
    print(f"Marked {marked} of {wanted} deprecated operations")
    # A deprecated operation with no method means the generator skipped it or
    # changed the text OPERATION matches. Either way callers lose the warning.
    if marked != wanted:
        failed = True

    if failed:
        # Either the generator fixed the defect upstream, or it changed its
        # output and the defect is back unpatched. Both need a human, and both
        # have to stop the release. The workflow turns this into an issue.
        print(
            "\nA fix matched nothing. Check whether openapi-generator (pinned in "
            "the Makefile) changed its output, or fixed this upstream, in which "
            "case delete the fix here.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <lib-dir> <openapi.json>", file=sys.stderr)
        raise SystemExit(2)
    raise SystemExit(main(sys.argv[1], sys.argv[2]))
