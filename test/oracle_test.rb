# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../libs/connectors/oracle'

class OracleTest < Minitest::Test
  class FakeCursor
    attr_accessor :exec_error, :fetch_error, :bind_error, :close_error
    attr_reader :bindings, :close_count

    def initialize(rows = [[1, 'Ana'], [2, 'João']])
      @rows = rows
      @bindings = {}
      @close_count = 0
    end

    def bind_param(name, value)
      raise bind_error if bind_error

      @bindings[name] = value
    end

    def exec
      raise exec_error if exec_error

      2
    end

    def fetch
      raise fetch_error if fetch_error

      @rows.each { |row| yield row }
    end

    def close
      @close_count += 1
      raise close_error if close_error
    end
  end

  class FakeConnection
    attr_reader :cursor, :sql, :commits, :rollbacks, :logoffs
    attr_accessor :parse_error, :logoff_error

    def initialize(cursor = FakeCursor.new)
      @cursor = cursor
      @commits = @rollbacks = @logoffs = 0
    end

    def parse(sql)
      raise parse_error if parse_error

      @sql = sql
      @cursor
    end

    def commit
      @commits += 1
    end

    def rollback
      @rollbacks += 1
    end

    def logoff
      @logoffs += 1
      raise logoff_error if logoff_error
    end
  end

  def setup
    @connection = FakeConnection.new
    @cursor = @connection.cursor
    @oracle = Connector::Oracle.new(connection: @connection)
  end

  def test_array_query_closes_cursor
    assert_equal [[1, 'Ana'], [2, 'João']], @oracle.consulta_retorno('SELECT id, nome FROM pessoas')
    assert_equal 1, @cursor.close_count
  end

  def test_empty_query_result
    oracle = Connector::Oracle.new(connection: FakeConnection.new(FakeCursor.new([])))
    assert_empty oracle.consulta_retorno('SELECT id FROM pessoas')
  end

  def test_named_bindings_are_not_interpolated_into_sql
    sql = 'SELECT id FROM pessoas WHERE nome = :nome'
    value = "x' OR '1'='1"
    @oracle.consulta_retorno(sql, nome: value)
    assert_equal sql, @connection.sql
    assert_equal({ nome: value }, @cursor.bindings)
  end

  def test_typed_null_and_positional_bindings
    params = { 1 => { value: nil, type: Integer } }
    assert_equal 2, @oracle.executar('UPDATE pessoas SET idade = :1', params)
    assert_equal params, @cursor.bindings
    assert_equal 1, @cursor.close_count
  end

  def test_query_without_block_returns_open_cursor
    assert_same @cursor, @oracle.consultar('SELECT id FROM pessoas')
    assert_equal 0, @cursor.close_count
    @cursor.close
  end

  def test_query_with_block_closes_cursor_and_returns_block_result
    assert_equal :result, @oracle.consultar('SELECT id FROM pessoas') { :result }
    assert_equal 1, @cursor.close_count
  end

  def test_streaming_query_yields_rows_and_closes_cursor
    rows = []
    assert_same @oracle, @oracle.each_row('SELECT id FROM pessoas') { |row| rows << row }
    assert_equal [[1, 'Ana'], [2, 'João']], rows
    assert_equal 1, @cursor.close_count
  end

  def test_enumerator_is_lazy_and_closes_after_early_break
    enumerator = @oracle.each_row('SELECT id FROM pessoas')
    assert_nil @connection.sql
    assert_equal [[1, 'Ana']], enumerator.take(1)
    assert_equal 1, @cursor.close_count
  end

  def test_large_result_is_not_materialized_when_only_one_row_is_requested
    generated = 0
    rows = (1..100_000).lazy.map do |id|
      generated += 1
      [id]
    end
    cursor = FakeCursor.new(rows)
    oracle = Connector::Oracle.new(connection: FakeConnection.new(cursor))
    assert_equal [[1]], oracle.each_row('SELECT id FROM pessoas').take(1)
    assert_equal 1, generated
    assert_equal 1, cursor.close_count
  end

  def test_block_exception_closes_cursor
    error = assert_raises(RuntimeError) do
      @oracle.each_row('SELECT id FROM pessoas') { raise 'consumer failed' }
    end
    assert_equal 'consumer failed', error.message
    assert_equal 1, @cursor.close_count
  end

  def test_fetch_exception_closes_cursor
    @cursor.fetch_error = RuntimeError.new('fetch failed')
    assert_raises(RuntimeError) { @oracle.consulta_retorno('SELECT id FROM pessoas') }
    assert_equal 1, @cursor.close_count
  end

  def test_execution_exception_closes_cursor_even_without_block
    @cursor.exec_error = RuntimeError.new('exec failed')
    assert_raises(RuntimeError) { @oracle.consultar('SELECT id FROM pessoas') }
    assert_equal 1, @cursor.close_count
  end

  def test_bind_exception_closes_cursor
    @cursor.bind_error = RuntimeError.new('bind failed')
    assert_raises(RuntimeError) { @oracle.executar('UPDATE pessoas SET idade = :idade', idade: 20) }
    assert_equal 1, @cursor.close_count
  end

  def test_dml_error_closes_cursor
    @cursor.exec_error = RuntimeError.new('update failed')
    assert_raises(RuntimeError) { @oracle.executar('UPDATE pessoas SET idade = 20') }
    assert_equal 1, @cursor.close_count
  end

  def test_parse_error_is_not_masked_by_cleanup
    error = RuntimeError.new('parse failed')
    @connection.parse_error = error
    assert_same error, assert_raises(RuntimeError) { @oracle.executar('UPDATE pessoas SET idade = 20') }
    assert_equal 0, @cursor.close_count
  end

  def test_invalid_sql_and_bindings_are_rejected_before_parse
    [nil, '', '  ', 123].each do |sql|
      assert_raises(ArgumentError) { @oracle.executar(sql) }
    end
    assert_raises(ArgumentError) { @oracle.executar('SELECT 1 FROM dual', []) }
    assert_nil @connection.sql
  end

  def test_commit_and_rollback_are_explicit
    @oracle.executar('UPDATE pessoas SET idade = 20')
    assert_equal 0, @connection.commits
    @oracle.commit
    @oracle.rollback
    assert_equal 1, @connection.commits
    assert_equal 1, @connection.rollbacks
  end

  def test_close_is_idempotent_and_closed_connection_cannot_be_reused
    2.times { @oracle.close }
    assert @oracle.closed?
    assert_equal 1, @connection.logoffs
    assert_raises(IOError) { @oracle.commit }
    assert_raises(IOError) { @oracle.rollback }
    assert_raises(IOError) { @oracle.consultar('SELECT 1 FROM dual') }
  end

  def test_block_connection_closes_on_success
    result = Connector::Oracle.open(connection: @connection) { :result }
    assert_equal :result, result
    assert_equal 1, @connection.logoffs
    assert_equal 0, @connection.commits
  end

  def test_block_connection_closes_on_exception
    assert_raises(RuntimeError) do
      Connector::Oracle.open(connection: @connection) { raise 'failure' }
    end
    assert_equal 1, @connection.logoffs
  end

  def test_missing_configuration_is_reported_without_loading_driver
    error = assert_raises(ArgumentError) { Connector::Oracle.new({}) }
    assert_includes error.message, 'host, user, password'
  end

  def test_cursor_cleanup_does_not_replace_query_error
    primary = RuntimeError.new('query failed')
    cleanup = IOError.new('cursor close failed')
    @cursor.exec_error = primary
    @cursor.close_error = cleanup
    _, stderr = capture_io do
      error = assert_raises(RuntimeError) { @oracle.executar('UPDATE pessoas SET idade = 20') }
      assert_same primary, error
    end
    assert_includes stderr, cleanup.message
  end

  def test_connection_cleanup_does_not_replace_block_error
    primary = RuntimeError.new('business operation failed')
    cleanup = IOError.new('logoff failed')
    @connection.logoff_error = cleanup
    _, stderr = capture_io do
      error = assert_raises(RuntimeError) do
        Connector::Oracle.open(connection: @connection) { raise primary }
      end
      assert_same primary, error
    end
    assert_includes stderr, cleanup.message
  end

  def test_cleanup_failure_is_reported_when_query_succeeds
    cleanup = IOError.new('cursor close failed')
    @cursor.close_error = cleanup
    error = assert_raises(IOError) { @oracle.executar('UPDATE pessoas SET idade = 20') }
    assert_same cleanup, error
  end

  def test_connection_is_unusable_after_logoff_error
    @connection.logoff_error = IOError.new('logoff failed')
    assert_raises(IOError) { @oracle.close }
    assert @oracle.closed?
    @oracle.close
    assert_equal 1, @connection.logoffs
    assert_raises(IOError) { @oracle.commit }
  end

  def test_configuration_must_be_a_hash
    [123, 'not a config', []].each do |config|
      assert_raises(ArgumentError) { Connector::Oracle.new(config) }
    end
  end
end
