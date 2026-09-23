# Working on this repo

Everything under `lib/` is generated except four files, and the
next release overwrites the rest. Changes to the API surface come from the
upstream OpenAPI schema. Changes to the *shape* of the generated code come from
`scripts/prepare_spec.py` (before generation) and `scripts/fix_generated.py`
(after).

Hand-written and safe to edit:

- `lib/incident_io_api.rb`, `lib/incident_io/version.rb`,
  `lib/incident_io/errors.rb` and `lib/incident_io/deprecation.rb`
- `spec/`, `scripts/`, `templates/`, `.github/`
- `incident_io.gemspec`, `Gemfile`, `Makefile`, `README.md` and this file

`.openapi-generator-ignore` lists them, so the generator leaves them alone.
The generator's per-file markdown docs and stub specs are switched off in the
`Makefile`; rubydoc.info builds the reference from source.

## Prerequisites

| Tool | Needed by | Notes |
| --- | --- | --- |
| Ruby 3.0 or later, with Bundler | everything | CI tests every minor from 3.0 to 4.0 |
| Java 11 or later | `make generate`, `make template-drift` | openapi-generator is a jar; the Makefile downloads it to `/tmp` |
| Python 3 | `make generate` | runs the two passes in `scripts/` |
| network | `make package`, `make oasdiff` | `gem install` resolves dependencies from RubyGems, and `make oasdiff` fetches the live schema |

Run `bundle install` once before `make test`.

## Targets

`make help` lists them. The ones that matter:

- `make generate`: regenerate from the **committed** `openapi.json`. It writes
  the prepared schema to `build/`, regenerates `lib/`, then applies the
  post-generation pass. Start here after changing anything in `scripts/`.
- `make verify`: the stand-in for a compile step. Compiles every file, builds
  the gem, installs it into `.verify/`, loads every constant from the
  *installed* gem, and checks the API surface.
- `make test`: `make verify`, then the specs. This is what CI runs.
- `make surface`: accept the current API surface as the baseline, removals
  included. Only alongside a major version.
- `make template-drift`: fail if the generator's templates changed under the
  anchors `scripts/fix_generated.py` matches on.
- `make oasdiff`: the schema gate that stops a release, runnable by hand.
- `make smoke`: read-only checks against the live API. Needs
  `INCIDENT_API_KEY`; a viewer-scoped key is enough.

## How a release happens

`.github/workflows/sync.yml`, hourly. When the live schema differs from the
committed one it regenerates, verifies on the release Ruby and builds on the
minimum Ruby, bumps the **minor** version, commits, tags, and pushes the gem
to RubyGems. No human unless a gate trips.

Two gates stop it:

- **oasdiff** compares the schemas, with the adjustments in
  `oasdiff-severity.txt`.
- **The API surface check** in `make verify` compares the Ruby API against
  `api-surface.txt`: one line per API method (with its number of positional
  arguments), per model attribute and per error class. A line that disappears
  fails the release. This catches what oasdiff rates harmless but a caller
  does not: an operation moved to another tag moves its method to another
  class, and a renamed component schema renames a class. When nothing
  disappeared, the check writes additions into `api-surface.txt`, and the
  release commits it.

Either one halting the run leaves the new schema uncommitted, so every later
run sees the same diff and halts the same way until someone acts. That is
deliberate, and why the issue it files is deduped.

To release a breaking change: run `make surface` if the Ruby API lost names
and commit `api-surface.txt`, then run the workflow from the Actions tab with
**bump: major** and **acknowledge_breaking: true**. Both are required
together.

### Why the generated code is shaped the way it is

Our API compatibility policy treats adding a response property, a request
property, an enum value or an optional parameter as backwards-compatible, and
those ship without a human.

- **Response properties**: the generated models already ignore keys they do
  not know.
- **Optional parameters**: they arrive in the trailing `opts` hash, so adding
  one changes no signature.
- **Enum values**: not safe as generated. Every enum is validated in a model
  setter, and building a model from a response goes through the setters, so a
  new value raises for the whole response on every installed copy of the gem.
  `scripts/prepare_spec.py` turns enums into plain strings before generating.
  Its docstring has the full argument, including why the generator's own
  `enumUnknownDefaultCase` is worse.

The other changes fix the generator's defaults, not compatibility: the error
hierarchy (an `ApiError.new` override in `errors.rb`), deprecation markers,
the missing `cgi/escape` require, raw NUL bytes in regex literals, method names
like `a_pi_keys_v1_create`, and a 7.7KB header comment in every file. Each is
documented where it is made.

The client is generated with `useAutoload=true`. Requiring the gem registers
~1,200 autoloads instead of loading every file: about 70ms and 17MB at boot,
against about 490ms and 61MB. `make verify` fails if that stops being true.

## The gem name

The gem is published as `incident_io_api`. The library is `require
"incident_io"` and the module `IncidentIo`; `lib/incident_io_api.rb` requires
it, so `Bundler.require`, which loads a gem by its own name, works too.

`incident_io` itself is unavailable. A gem named `incident-io` exists,
published in May 2024 by an account unconnected to incident.io and containing
only a README. RubyGems ignores `-` and `_` when checking a new name for
typosquatting and protects any gem released in the last five years, so it
blocks `incident_io` and `incidentio` until May 2029. `incident_io_sdk` is an
unofficial generated client (module `IncidentIoSdk`) and blocks
`incident-io-sdk`.

Underscores rather than `incident-io-api`, following the RubyGems naming
guide: a dash marks a namespace, so that name would promise
`require "incident/io/api"` and `Incident::Io::Api`.

## Keeping the loop alive

Everything that reports a problem here is a `failure()` hook, and a loop that
never runs never fails. GitHub **disables a scheduled workflow after 60 days**
with no repository activity, and this repo's activity is its own release
commits, which stop exactly when the schema stops changing. Each run writes a
line to its job summary saying what it decided. If the run list is empty for a
week, the loop is off, not quiet.

## Upgrading openapi-generator

`OPENAPI_GENERATOR_VERSION` in the `Makefile` is pinned deliberately. The
project ships no patch releases, so every available upgrade is a minor, which
its own policy says may change template-bound variables, and those are what
`scripts/fix_generated.py` anchors on.

1. Change the version and run `make template-drift`. It will fail and print
   the diff against `templates/pristine/`.
2. Read the diff. Decide whether each fix in `scripts/fix_generated.py` still
   applies.
3. Copy the new templates over `templates/pristine/`, run `make generate`, and
   check the pass still reports every fix and all deprecated operations.
4. `make test`. A method or class that changed name fails the surface check;
   that is a breaking change, not something to accept with `make surface`.
