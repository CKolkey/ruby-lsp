# typed: strict
# frozen_string_literal: true

require "ruby_lsp/internal"
require "objspace"

module RubyLsp
  # This rake task checks that all requests or extensions are fully documented. Add the rake task to your Rakefile and
  # specify the absolute path for all files that must be required in order to discover all listeners
  #
  #   # Rakefile
  #   request_files = FileList.new("#{__dir__}/lib/ruby_lsp/requests/*.rb") do |fl|
  #     fl.exclude(/base_request\.rb/)
  #   end
  #   RubyLsp::CheckDocs.new(request_files)
  #   # Run with bundle exec rake ruby_lsp:check_docs
  class CheckDocs < Rake::TaskLib
    extend T::Sig

    sig { params(require_files: Rake::FileList).void }
    def initialize(require_files)
      super()

      @name = T.let("ruby_lsp:check_docs", String)
      @file_list = require_files
      define_task
    end

    private

    sig { void }
    def define_task
      desc("Checks if all Ruby LSP listeners are documented")
      task(@name) { run_task }
    end

    sig { void }
    def run_task
      # Require all files configured to make sure all listeners are loaded
      @file_list.each { |f| require(f.delete_suffix(".rb")) }

      # Find all classes that inherit from BaseRequest or Listener, which are the ones we want to make sure are
      # documented
      features = ObjectSpace.each_object(Class).filter_map do |k|
        klass = T.cast(k, Class)
        klass if klass < RubyLsp::Requests::BaseRequest || klass < RubyLsp::Listener
      end

      missing_docs = T.let(Hash.new { |h, k| h[k] = [] }, T::Hash[String, T::Array[String]])

      features.each do |klass|
        class_name = T.must(klass.name)
        file_path, line_number = Module.const_source_location(class_name)
        next unless file_path && line_number

        # Adjust the line number to start searching right above the class definition
        line_number -= 2

        lines = File.readlines(file_path)
        docs = []

        # Extract the documentation on top of the listener constant
        while (line = lines[line_number]&.strip) && line.start_with?("#")
          docs.unshift(line)
          line_number -= 1
        end

        documentation = docs.join("\n")

        if docs.empty?
          T.must(missing_docs[class_name]) << "No documentation found"
        elsif !%r{\(https://microsoft.github.io/language-server-protocol/specification#.*\)}.match?(documentation)
          T.must(missing_docs[class_name]) << <<~DOCS
            Missing specification link. Requests and extensions should include a link to the LSP specification for the
            related feature. For example:

            [Inlay hint](https://microsoft.github.io/language-server-protocol/specification#textDocument_inlayHint)
          DOCS
        elsif !documentation.include?("# Example")
          T.must(missing_docs[class_name]) << <<~DOCS
            Missing example. Requests and extensions should include a code example that explains what the feature does.

            # # Example
            # ```ruby
            # class Foo # <- information is shown here
            # end
            # ```
          DOCS
        elsif !/\[.* demo\]\(.*\.gif\)/.match?(documentation)
          T.must(missing_docs[class_name]) << <<~DOCS
            Missing demonstration GIF. Each request and extension must be documented with a GIF that shows the feature
            working. For example:

            # [Inlay hint demo](../../inlay_hint.gif)
          DOCS
        end
      end

      if missing_docs.any?
        warn(<<~WARN)
          The following listeners are missing documentation:

          #{missing_docs.map { |k, v| "#{k}\n\n#{v.join("\n")}" }.join("\n\n")}
        WARN

        abort
      end

      puts "All listeners are documented!"
    end
  end
end
