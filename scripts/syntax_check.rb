# frozen_string_literal: true

# Compile every file under lib/ without running it.
#
# Loading the gem only reaches what autoload is asked for, so a syntax error in
# a model nothing touches would ship. One process rather than `ruby -c` per
# file, which is 1,200 interpreter start-ups.

root = ARGV.fetch(0) { abort "usage: ruby #{$PROGRAM_NAME} <lib-dir>" }
files = Dir.glob(File.join(root, "**", "*.rb")).sort

# A floor, because the count on its own proves nothing: a generator that
# silently dropped every model would compile perfectly. The real figure is
# ~1,200; this only catches collapse.
MINIMUM_FILES = 1000
abort "syntax_check: only #{files.size} files under #{root}, expected at least #{MINIMUM_FILES}" if files.size < MINIMUM_FILES

failures = files.filter_map do |file|
  source = File.binread(file).force_encoding(Encoding::UTF_8)
  next "#{file}: contains a NUL byte" if source.include?("\0")
  next "#{file}: not valid UTF-8" unless source.valid_encoding?

  RubyVM::InstructionSequence.compile(source, file)
  nil
rescue SyntaxError => e
  "#{file}: #{e.message}"
end

unless failures.empty?
  warn failures
  abort "syntax_check: #{failures.size} file(s) failed"
end

puts "syntax_check: compiled #{files.size} files"
