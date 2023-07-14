# typed: true
# frozen_string_literal: true

require "test_helper"

class ShowSyntaxTreeTest < Minitest::Test
  def setup
    @message_queue = Thread::Queue.new
  end

  def teardown
    @message_queue.close
  end

  def test_returns_nil_if_document_has_syntax_error
    store = RubyLsp::Store.new
    store.set(uri: "file:///fake.rb", source: "foo do", version: 1)
    response = RubyLsp::Executor.new(store, @message_queue).execute({
      method: "rubyLsp/textDocument/showSyntaxTree",
      params: { textDocument: { uri: "file:///fake.rb" } },
    }).response

    assert_equal("Document contains syntax error", response[:ast])
  end

  def test_returns_ast_if_document_is_parsed
    store = RubyLsp::Store.new
    store.set(uri: "file:///fake.rb", source: "foo = 123", version: 1)
    document = store.get("file:///fake.rb")
    document.parse

    response = RubyLsp::Executor.new(store, @message_queue).execute({
      method: "rubyLsp/textDocument/showSyntaxTree",
      params: { textDocument: { uri: "file:///fake.rb" } },
    }).response

    assert_equal(<<~AST, response[:ast])
      (program (statements ((assign (var_field (ident "foo")) (int "123")))))
    AST
  end
end