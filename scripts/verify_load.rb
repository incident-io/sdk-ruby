# frozen_string_literal: true

# Load all of the installed gem, then check its public surface against the
# committed baseline.
#
#   ruby scripts/verify_load.rb check api-surface.txt  # fail on removals, record additions
#   ruby scripts/verify_load.rb write api-surface.txt  # accept removals too
#
# Run against the installed gem, not the working tree (make verify arranges
# that), so this checks what we would publish.
#
# Loading: `require "incident_io"` only registers autoloads, so on its own it
# proves nothing about the 1,200 files behind them. This resolves every one,
# which catches an autoload pointing at a path the gem does not contain and a
# file that parses but fails when run.
#
# Surface: the release gate is oasdiff, which compares schemas. What we publish
# is Ruby generated from that schema, and the two disagree about what breaks.
# Moving an operation to another tag, or renaming a component schema, is
# `info` to oasdiff because nothing on the wire changes, while it renames a
# class that callers reference:
#
#   NameError: uninitialized constant IncidentIo::SeverityV1
#
# So this records the Ruby surface, one line per name, and fails when any line
# disappears. Additions are fine; removals are not. One line per name rather
# than per class, because a composite line would be rewritten whenever anything
# on it changed, so adding a field would read as a removal.

mode, path = ARGV
abort "usage: ruby #{$PROGRAM_NAME} check|write <api-surface.txt>" unless %w[check write].include?(mode) && path

# The gem's own name, as Bundler.require would load it. That file loads
# incident_io, so this covers both.
gem_name = Gem::Specification.load(File.expand_path("../incident_io.gemspec", __dir__)).name
require gem_name

loaded_from = Gem.loaded_specs[gem_name]&.full_gem_path
if ENV["GEM_HOME"] && !loaded_from.to_s.start_with?(ENV["GEM_HOME"])
  abort "verify_load: loaded #{loaded_from || "#{gem_name} from outside RubyGems"}, not the gem installed under #{ENV['GEM_HOME']}"
end

# Checked before anything resolves a constant, since that is what the check is
# about: requiring the gem must not load every model. Eager loading costs about
# 400ms and 45MB of RSS at boot.
abort "verify_load: models are not autoloaded; boot will load all of them" unless IncidentIo.autoload?(:ActionV1)

# Resolving every constant is the load check.
classes = IncidentIo.constants.sort.map { |name| IncidentIo.const_get(name) }.grep(Class)
apis = classes.select { |klass| klass.name.end_with?("Api") && klass.method_defined?(:api_client) }
models = classes.select { |klass| klass.respond_to?(:openapi_types) }
errors = classes.select { |klass| klass <= IncidentIo::ApiError }

# Floors, because a clean load proves nothing about size: a schema that
# generated five models loads perfectly. Real figures are ~59, ~1,130 and 9;
# these only catch collapse.
{ "API classes" => [apis, 50], "models" => [models, 1000], "error classes" => [errors, 9] }.each do |what, (found, floor)|
  abort "verify_load: only #{found.size} #{what}, expected at least #{floor}" if found.size < floor
end

puts "verify_load: loaded #{apis.size} API classes, #{models.size} models and #{errors.size} error classes"

surface = []
apis.each do |api|
  (api.public_instance_methods(false) - %i[api_client api_client=]).sort.each do |method|
    # Positional arguments are the path parameters and the body, so their
    # count is what a caller's call site depends on. Their names are not:
    # nobody passes a positional argument by name. Optional parameters arrive
    # in the opts hash, where an unknown key is ignored.
    required = api.instance_method(method).parameters.count { |type, _| type == :req }
    surface << "api #{api.name}##{method} #{required}"
  end
end
models.each do |model|
  model.openapi_types.keys.sort.each { |attribute| surface << "model #{model.name} #{attribute}" }
end
errors.each { |klass| surface << "error #{klass.name}" }
surface.sort!

if mode == "check" && !File.exist?(path)
  abort "verify_load: #{path} is missing. Run `make surface` to record a baseline."
end

baseline = File.exist?(path) ? File.readlines(path, chomp: true) : []
removed = mode == "write" ? [] : baseline - surface
added = surface - baseline

if removed.any?
  warn "verify_load: #{removed.size} name(s) left the public surface:"
  warn removed.first(50).map { |line| "  - #{line}" }
  warn "  ... and #{removed.size - 50} more" if removed.size > 50
  warn ""
  warn "Each one breaks a caller that uses it. If this is a deliberate major"
  warn "release, run `make surface` and commit api-surface.txt with it."
  exit 1
end

# In check mode, record the additions, so the next release checks against
# them. Leaving the baseline alone would mean a name added in one release and
# removed in the next was never on it, and the removal would pass.
File.write(path, surface.join("\n") + "\n") if mode == "write" || added.any?
puts "verify_load: surface ok (#{surface.size} lines, #{added.size} added, #{(baseline - surface).size} removed)"
