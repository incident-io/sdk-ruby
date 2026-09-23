# Pinned deliberately. openapi-generator ships no patch releases and no major
# since 2023, so every available upgrade is a minor, which is the tier its own
# policy says may change template-bound variables. Bumping this is a
# human-reads-the-diff operation, never automatic. See CONTRIBUTING.md.
OPENAPI_GENERATOR_VERSION := 7.25.0

# Pinned for the same reason as the generator: it decides whether we publish.
# The release workflow gets its copy through `make oasdiff-bin`, so this is the
# only pin.
OASDIFF_VERSION  := 1.32.1
# Versioned, like the generator jar: an unversioned path would keep serving a
# stale binary after OASDIFF_VERSION is bumped.
OASDIFF          := /tmp/oasdiff-$(OASDIFF_VERSION)
# oasdiff ships one universal darwin build and per-arch linux builds.
OASDIFF_OS       := $(shell uname -s | tr 'A-Z' 'a-z')
OASDIFF_PLATFORM := $(if $(filter darwin,$(OASDIFF_OS)),darwin_all,$(OASDIFF_OS)_$(shell uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/'))

GENERATOR  := /tmp/openapi-generator-cli-$(OPENAPI_GENERATOR_VERSION).jar
SCHEMA_URL := https://api.incident.io/v1/openapiV3.json
PREPARED   := build/openapi.json
# Interpolated by Ruby at load time, so it always names the installed version.
# The backslash stops make reading the # as a comment.
USER_AGENT := incident-io-sdk-ruby/\#{VERSION}

# The gem is installed here by make package, so the checks load what we would
# publish rather than the working tree.
VERIFY_GEM_HOME := $(CURDIR)/.verify
VERIFY_ENV      := GEM_HOME=$(VERIFY_GEM_HOME) GEM_PATH=$(VERIFY_GEM_HOME)

.DEFAULT_GOAL := help
.PHONY: help fetch generate package verify test surface smoke template-drift oasdiff oasdiff-bin clean

help:
	@grep -E '^[a-z-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

# -L because without it a redirect is a silent success writing zero bytes,
# which parses as an empty schema. OUT lets the release workflow fetch to a
# scratch path so it still has the previous schema to diff against.
OUT ?= openapi.json

fetch: ## Fetch the live schema (OUT= to write elsewhere)
	curl -sfSL $(SCHEMA_URL) -o $(OUT)

$(GENERATOR):
	curl -sfSL -o $@ \
		https://repo1.maven.org/maven2/org/openapitools/openapi-generator-cli/$(OPENAPI_GENERATOR_VERSION)/openapi-generator-cli-$(OPENAPI_GENERATOR_VERSION).jar

# .openapi-generator-ignore keeps the generator out of the gemspec, README and
# the rest: the ruby generator has no --meta none, and it would otherwise
# overwrite the packaged file list and the release version on every run.
generate: openapi.json $(GENERATOR) ## Regenerate the client from the committed schema
	python3 scripts/prepare_spec.py openapi.json $(PREPARED)
	# Cleared first: the generator only writes, never deletes, so an endpoint or
	# model removed upstream would otherwise leave a stale file behind, still
	# loadable by path and committed forever. Not lib/ itself, because
	# version.rb, errors.rb and deprecation.rb are hand-written.
	rm -rf lib/incident_io/api lib/incident_io/models
	# The global properties skip the per-file markdown docs and stub specs,
	# which nothing reads: docs are built from source by rubydoc.info.
	java -jar $(GENERATOR) generate \
		--input-spec $(PREPARED) \
		--generator-name ruby \
		--library faraday \
		--output . \
		--global-property=apis,models,supportingFiles,apiDocs=false,modelDocs=false,apiTests=false,modelTests=false \
		--additional-properties=gemName=incident_io,moduleName=IncidentIo,useAutoload=true,httpUserAgent='$(USER_AGENT)' \
		> /tmp/openapi-generator.log 2>&1 || (tail -40 /tmp/openapi-generator.log && exit 1)
	python3 scripts/fix_generated.py lib openapi.json

# Ruby has no compile step, so this stands in for one. Each stage catches
# something the one before it cannot: a syntax error in a file nothing loads,
# a gemspec that packages the wrong files, and a constant that autoloads a path
# that is not in the gem.
package: ## Syntax-check, build the gem and install it into .verify/
	ruby scripts/syntax_check.rb lib
	rm -rf pkg $(VERIFY_GEM_HOME)
	mkdir -p pkg
	gem build incident_io.gemspec --output pkg/incident_io.gem
	$(VERIFY_ENV) gem install --no-document pkg/incident_io.gem

# From /, and with GEM_PATH pointed only at what package just installed, so
# nothing can resolve against the working tree by accident.
VERIFY_LOAD := cd / && $(VERIFY_ENV) ruby $(CURDIR)/scripts/verify_load.rb

verify: package ## Package, load every constant, and check the API surface
	$(VERIFY_LOAD) check $(CURDIR)/api-surface.txt

test: verify ## Everything verify does, plus the specs
	bundle exec rspec

# Accept the current surface as the new baseline, removals included. Run after
# a deliberate breaking change, alongside the major version bump.
surface: package ## Rewrite api-surface.txt from the installed gem
	$(VERIFY_LOAD) write $(CURDIR)/api-surface.txt

smoke: ## Read-only checks against the live API (needs INCIDENT_API_KEY)
	ruby -Ilib scripts/smoke_test.rb

# We deliberately do not fork the generator's templates; scripts/
# fix_generated.py explains why. templates/pristine/ holds unmodified upstream
# copies, used for nothing but this check. The generator is never invoked
# with -t.
#
# The check exists because rewriting generated text anchors on what the
# templates emit. An upstream edit to a template shows up as a pass matching
# nothing, which stops the release; an upstream *rename or split* of the file
# would not show up at all. So assert both: the template still exists under the
# same name, and it still says what the anchors were written against.
template-drift: $(GENERATOR) ## Fail if the generator's templates moved under us
	rm -rf /tmp/upstream-ruby-templates
	java -jar $(GENERATOR) author template --generator-name ruby --library faraday --output /tmp/upstream-ruby-templates >/dev/null 2>&1
	# Every file in templates/pristine/ is one a pass anchors on. diff also
	# fails, and says so, when upstream renamed or removed the file.
	@rc=0; for f in templates/pristine/*.mustache; do \
		diff -u "$$f" "/tmp/upstream-ruby-templates/$${f##*/}" || rc=1; \
	done; \
	[ $$rc = 0 ] || { echo ""; \
		echo "The generator's templates changed. Read the diff, re-check that"; \
		echo "scripts/fix_generated.py still applies, then copy the new files over"; \
		echo "templates/pristine/."; exit 1; }

# The gate that stops an unattended release, runnable by hand. The
# stuck-release issue names it as a likely cause, so it needs a command.
oasdiff: $(OASDIFF) ## Diff the live schema against the committed one, as the release does
	@$(MAKE) --no-print-directory fetch OUT=/tmp/openapi.json.new
	@python3 scripts/check_schema.py /tmp/openapi.json.new
	$(OASDIFF) breaking openapi.json /tmp/openapi.json.new \
		--severity-levels oasdiff-severity.txt --fail-on ERR

# Prints the path, so the release workflow runs the same pinned binary. It
# invokes it itself because it has to tell oasdiff's exit codes apart, which
# make would collapse.
oasdiff-bin: $(OASDIFF)
	@echo $(OASDIFF)

$(OASDIFF):
	curl -sfSL "https://github.com/oasdiff/oasdiff/releases/download/v$(OASDIFF_VERSION)/oasdiff_$(OASDIFF_VERSION)_$(OASDIFF_PLATFORM).tar.gz" \
		| tar -xzO oasdiff > $@
	chmod +x $@

# Not .openapi-generator: its FILES and VERSION are tracked and go into the
# release commit.
clean: ## Remove build output
	rm -rf build pkg $(VERIFY_GEM_HOME)
