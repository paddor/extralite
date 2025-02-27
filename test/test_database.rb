# frozen_string_literal: true

require_relative 'helper'

require 'date'
require 'tempfile'

class DatabaseTest < MiniTest::Test
  def setup
    @db = Extralite::Database.new(':memory:')
    @db.query('create table if not exists t (x,y,z)')
    @db.query('delete from t')
    @db.query('insert into t values (1, 2, 3)')
    @db.query('insert into t values (4, 5, 6)')
  end

  def test_database
    r = @db.query('select 1 as foo')
    assert_equal [{foo: 1}], r
  end

  def test_query
    r = @db.query('select * from t')
    assert_equal [{x: 1, y: 2, z: 3}, {x: 4, y: 5, z: 6}], r

    r = @db.query('select * from t where x = 2')
    assert_equal [], r
  end

  def test_invalid_query
    assert_raises(Extralite::SQLError) { @db.query('blah') }
  end

  def test_query_hash
    r = @db.query_hash('select * from t')
    assert_equal [{x: 1, y: 2, z: 3}, {x: 4, y: 5, z: 6}], r

    r = @db.query_hash('select * from t where x = 2')
    assert_equal [], r
  end

  def test_query_ary
    r = @db.query_ary('select * from t')
    assert_equal [[1, 2, 3], [4, 5, 6]], r

    r = @db.query_ary('select * from t where x = 2')
    assert_equal [], r
  end

  def test_query_single_row
    r = @db.query_single_row('select * from t order by x desc limit 1')
    assert_equal({ x: 4, y: 5, z: 6 }, r)

    r = @db.query_single_row('select * from t where x = 2')
    assert_nil r
  end

  def test_query_single_column
    r = @db.query_single_column('select y from t')
    assert_equal [2, 5], r

    r = @db.query_single_column('select y from t where x = 2')
    assert_equal [], r
  end

  def test_query_single_value
    r = @db.query_single_value('select z from t order by Z desc limit 1')
    assert_equal 6, r

    r = @db.query_single_value('select z from t where x = 2')
    assert_nil r
  end

  def test_columns
    r = @db.columns('select x, z from t')
    assert_equal [:x, :z], r
  end

  def test_transaction_active?
    assert_equal false, @db.transaction_active?
    @db.query('begin')
    assert_equal true, @db.transaction_active?
    @db.query('rollback')
    assert_equal false, @db.transaction_active?
  end

  def test_multiple_statements
    @db.query("insert into t values ('a', 'b', 'c'); insert into t values ('d', 'e', 'f');")

    assert_equal [1, 4, 'a', 'd'], @db.query_single_column('select x from t order by x')
  end

  def test_multiple_statements_with_error
    error = nil
    begin
      @db.query("insert into t values foo; insert into t values ('d', 'e', 'f');")
    rescue => error
    end

    assert_kind_of Extralite::SQLError, error
    assert_equal 'near "foo": syntax error', error.message
  end

  def test_empty_sql
    r = @db.query(' ')
    assert_nil r

    r = @db.query('select 1 as foo;  ')
    assert_equal [{ foo: 1 }], r
  end

  def test_close
    assert_equal false, @db.closed?
    r = @db.query_single_value('select 42')
    assert_equal 42, r

    assert_equal @db, @db.close
    assert_equal true, @db.closed?

    assert_raises(Extralite::Error) { @db.query_single_value('select 42') }
  end

  def test_parameter_binding_simple
    r = @db.query('select x, y, z from t where x = ?', 1)
    assert_equal [{ x: 1, y: 2, z: 3 }], r

    r = @db.query('select x, y, z from t where z = ?', 6)
    assert_equal [{ x: 4, y: 5, z: 6 }], r

    error = assert_raises(Extralite::ParameterError) { @db.query_single_value('select ?', Date.today) }
    assert_equal error.message, 'Cannot bind parameter at position 1 of type Date'
  end

  def test_parameter_binding_with_index
    r = @db.query('select x, y, z from t where x = ?2', 0, 1)
    assert_equal [{ x: 1, y: 2, z: 3 }], r

    r = @db.query('select x, y, z from t where z = ?3', 3, 4, 6)
    assert_equal [{ x: 4, y: 5, z: 6 }], r
  end

  def test_parameter_binding_with_name
    r = @db.query('select x, y, z from t where x = :x', x: 1, y: 2)
    assert_equal [{ x: 1, y: 2, z: 3 }], r

    r = @db.query('select x, y, z from t where z = :zzz', 'zzz' => 6)
    assert_equal [{ x: 4, y: 5, z: 6 }], r

    r = @db.query('select x, y, z from t where z = :bazzz', ':bazzz' => 6)
    assert_equal [{ x: 4, y: 5, z: 6 }], r
  end

  def test_parameter_binding_with_index_key
    r = @db.query('select x, y, z from t where z = ?', 1 => 3)
    assert_equal [{ x: 1, y: 2, z: 3 }], r

    r = @db.query('select x, y, z from t where x = ?2', 1 => 42, 2 => 4)
    assert_equal [{ x: 4, y: 5, z: 6 }], r
  end

  class Foo; end

  def test_parameter_binding_from_hash
    assert_equal 42, @db.query_single_value('select :bar', foo: 41, bar: 42)
    assert_equal 42, @db.query_single_value('select :bar', 'foo' => 41, 'bar' => 42)
    assert_equal 42, @db.query_single_value('select ?8', 7 => 41, 8 => 42)
    assert_nil @db.query_single_value('select :bar', foo: 41)

    error = assert_raises(Extralite::ParameterError) { @db.query_single_value('select ?', Foo.new => 42) }
    assert_equal error.message, 'Cannot bind parameter with a key of type DatabaseTest::Foo'

    error = assert_raises(Extralite::ParameterError) { @db.query_single_value('select ?', %w[a b] => 42) }
    assert_equal error.message, 'Cannot bind parameter with a key of type Array'
  end

  def test_parameter_binding_from_struct
    foo_bar = Struct.new(:":foo", :bar)
    value = foo_bar.new(41, 42)
    assert_equal 41, @db.query_single_value('select :foo', value)
    assert_equal 42, @db.query_single_value('select :bar', value)
    assert_nil @db.query_single_value('select :baz', value)
  end

  def test_parameter_binding_from_data_class
    skip "Data isn't supported in Ruby < 3.2" if RUBY_VERSION < '3.2'

    foo_bar = Data.define(:":foo", :bar)
    value = foo_bar.new(":foo": 41, bar: 42)
    assert_equal 42, @db.query_single_value('select :bar', value)
    assert_nil @db.query_single_value('select :baz', value)
  end

  def test_parameter_binding_for_blobs
    sql = 'SELECT typeof(data) AS type, data FROM blobs WHERE ROWID = ?'
    blob_path = File.expand_path('fixtures/image.png', __dir__)
    @db.execute('CREATE TABLE blobs (data BLOB)')

    # it's a string, not a blob
    @db.execute('INSERT INTO blobs VALUES (?)', 'Hello, 世界!')
    result = @db.query_single_row(sql, @db.last_insert_rowid)
    assert_equal 'text', result[:type]
    assert_equal Encoding::UTF_8, result[:data].encoding

    data = File.binread(blob_path)
    @db.execute('INSERT INTO blobs VALUES (?)', data)
    result = @db.query_single_row(sql, @db.last_insert_rowid)
    assert_equal 'blob', result[:type]
    assert_equal data, result[:data]

    data = (+'Hello, 世界!').force_encoding(Encoding::ASCII_8BIT)
    @db.execute('INSERT INTO blobs VALUES (?)', data)
    result = @db.query_single_row(sql, @db.last_insert_rowid)
    assert_equal 'blob', result[:type]
    assert_equal Encoding::ASCII_8BIT, result[:data].encoding
    assert_equal 'Hello, 世界!', result[:data].force_encoding(Encoding::UTF_8)

    data = Extralite::Blob.new('Hello, 世界!')
    @db.execute('INSERT INTO blobs VALUES (?)', data)
    result = @db.query_single_row(sql, @db.last_insert_rowid)
    assert_equal 'blob', result[:type]
    assert_equal Encoding::ASCII_8BIT, result[:data].encoding
    assert_equal 'Hello, 世界!', result[:data].force_encoding(Encoding::UTF_8)
  end

  def test_parameter_binding_for_simple_types
    assert_nil @db.query_single_value('select ?', nil)

    # 32-bit integers
    assert_equal -2** 31, @db.query_single_value('select ?', -2**31)
    assert_equal 2**31 - 1, @db.query_single_value('select ?', 2**31 - 1)

    # 64-bit integers
    assert_equal -2 ** 63, @db.query_single_value('select ?', -2 ** 63)
    assert_equal 2**63 - 1, @db.query_single_value('select ?', 2**63 - 1)

    # floats
    assert_equal Float::MIN, @db.query_single_value('select ?', Float::MIN)
    assert_equal Float::MAX, @db.query_single_value('select ?', Float::MAX)

    # boolean
    assert_equal 1, @db.query_single_value('select ?', true)
    assert_equal 0, @db.query_single_value('select ?', false)

    # strings and symbols
    assert_equal 'foo', @db.query_single_value('select ?', 'foo')
    assert_equal 'foo', @db.query_single_value('select ?', :foo)
  end

  def test_value_casting
    r = @db.query_single_value("select 'abc'")
    assert_equal 'abc', r

    r = @db.query_single_value('select 123')
    assert_equal 123, r

    r = @db.query_single_value('select 12.34')
    assert_equal 12.34, r

    r = @db.query_single_value('select zeroblob(4)')
    assert_equal "\x00\x00\x00\x00", r

    r = @db.query_single_value('select null')
    assert_nil r
  end

  def test_extension_loading
    case RUBY_PLATFORM
    when /linux/
      @db.load_extension(File.join(__dir__, 'extensions/text.so'))
    when /darwin/
      @db.load_extension(File.join(__dir__, 'extensions/text.dylib'))
    end

    r = @db.query_single_value("select reverse('abcd')")
    assert_equal 'dcba', r
  end

  def test_tables
    assert_equal ['t'], @db.tables

    @db.query('create table foo (bar text)')
    assert_equal ['t', 'foo'], @db.tables

    @db.query('drop table t')
    assert_equal ['foo'], @db.tables

    @db.query('drop table foo')
    assert_equal [], @db.tables
  end

  def test_pragma
    assert_equal [{journal_mode: 'memory'}], @db.pragma('journal_mode')
    assert_equal [{synchronous: 2}], @db.pragma('synchronous')

    assert_equal [{schema_version: 1}], @db.pragma(:schema_version)
    assert_equal [{recursive_triggers: 0}], @db.pragma(:recursive_triggers)

    assert_equal [], @db.pragma(schema_version: 33, recursive_triggers: 1)
    assert_equal [{schema_version: 33}], @db.pragma(:schema_version)
    assert_equal [{recursive_triggers: 1}], @db.pragma(:recursive_triggers)
  end

  def test_execute
    changes = @db.execute('update t set x = 42')
    assert_equal 2, changes
  end

  def test_execute_with_params
    changes = @db.execute('update t set x = ? where z = ?', 42, 6)
    assert_equal 1, changes
    assert_equal [[1, 2, 3], [42, 5, 6]], @db.query_ary('select * from t order by x')
  end

  def test_execute_with_params_array
    changes = @db.execute('update t set x = ? where z = ?', [42, 6])
    assert_equal 1, changes
    assert_equal [[1, 2, 3], [42, 5, 6]], @db.query_ary('select * from t order by x')
  end

  def test_batch_execute
    @db.query('create table foo (a, b, c)')
    assert_equal [], @db.query('select * from foo')

    records = [
      [1, '2', 3],
      ['4', 5, 6]
    ]

    changes = @db.batch_execute('insert into foo values (?, ?, ?)', records)

    assert_equal 2, changes
    assert_equal [
      { a: 1, b: '2', c: 3 },
      { a: '4', b: 5, c: 6 }
    ], @db.query('select * from foo')
  end

  def test_batch_execute_single_values
    @db.query('create table foo (bar)')
    assert_equal [], @db.query('select * from foo')

    records = [
      'hi',
      'bye'
    ]

    changes = @db.batch_execute('insert into foo values (?)', records)

    assert_equal 2, changes
    assert_equal [
      { bar: 'hi' },
      { bar: 'bye' }
    ], @db.query('select * from foo')
  end

  def test_batch_execute_with_each_interface
    @db.query('create table foo (bar)')
    assert_equal [], @db.query('select * from foo')

    changes = @db.batch_execute('insert into foo values (?)', 1..3)

    assert_equal 3, changes
    assert_equal [
      { bar: 1 },
      { bar: 2 },
      { bar: 3 }
    ], @db.query('select * from foo')
  end

  def test_batch_execute_with_block
    source = [42, 43, 44]

    @db.query('create table foo (a)')
    assert_equal [], @db.query('select * from foo')

    changes = @db.batch_execute('insert into foo values (?)') { source.shift }

    assert_equal 3, changes
    assert_equal [
      { a: 42 },
      { a: 43 },
      { a: 44 }
    ], @db.query('select * from foo')
  end

  def test_interrupt
    t = Thread.new do
      sleep 0.5
      @db.interrupt
    end

    n = 2**31
    assert_raises(Extralite::InterruptError) {
      @db.query <<-SQL
        WITH RECURSIVE
          fibo (curr, next)
        AS
        ( SELECT 1,1
          UNION ALL
          SELECT next, curr+next FROM fibo
          LIMIT #{n} )
        SELECT curr, next FROM fibo LIMIT 1 OFFSET #{n}-1;
      SQL
    }
    t.join
  end

  def test_database_status
    assert_operator 0, :<, @db.status(Extralite::SQLITE_DBSTATUS_SCHEMA_USED).first
  end

  def test_database_limit
    result = @db.limit(Extralite::SQLITE_LIMIT_ATTACHED)
    assert_equal 10, result

    result = @db.limit(Extralite::SQLITE_LIMIT_ATTACHED, 5)
    assert_equal 10, result

    result = @db.limit(Extralite::SQLITE_LIMIT_ATTACHED)
    assert_equal 5, result

    assert_raises(Extralite::Error) { @db.limit(-999) }
  end

  def test_database_busy_timeout
    fn = Tempfile.new('extralite_test_database_busy_timeout').path
    db1 = Extralite::Database.new(fn)
    db2 = Extralite::Database.new(fn)

    db1.query('begin exclusive')
    assert_raises(Extralite::BusyError) { db2.query('begin exclusive') }

    db2.busy_timeout = 3
    t0 = Time.now
    t = Thread.new { sleep 0.1; db1.query('rollback') }
    result = db2.query('begin exclusive')
    t1 = Time.now

    assert_equal [], result
    assert t1 - t0 >= 0.1
    db2.query('rollback')
    t.join

    # try to provoke a timeout
    db1.query('begin exclusive')
    db2.busy_timeout = nil
    assert_raises(Extralite::BusyError) { db2.query('begin exclusive') }

    db2.busy_timeout = 0.2
    t0 = Time.now
    t = Thread.new do
      sleep 3
    ensure
      db1.query('rollback')
    end
    assert_raises(Extralite::BusyError) { db2.query('begin exclusive') }

    t1 = Time.now
    assert t1 - t0 >= 0.2
    t.kill
    t.join

    db1.query('begin exclusive')
    db2.busy_timeout = 0
    assert_raises(Extralite::BusyError) { db2.query('begin exclusive') }

    db2.busy_timeout = nil
    assert_raises(Extralite::BusyError) { db2.query('begin exclusive') }
  end

  def test_database_total_changes
    assert_equal 2, @db.total_changes

    @db.query('insert into t values (7, 8, 9)')

    assert_equal 3, @db.total_changes
  end

  def test_database_errcode_errmsg
    assert_equal 0, @db.errcode
    assert_equal 'not an error', @db.errmsg

    @db.query('select foo') rescue nil

    assert_equal 1, @db.errcode
    assert_equal 'no such column: foo', @db.errmsg

    if Extralite.sqlite3_version >= '3.38.5'
      assert_equal 7, @db.error_offset
    end

    @db.query('create table t2 (v not null)')

    assert_raises(Extralite::Error) { @db.query('insert into t2 values (null)') }
    assert_equal Extralite::SQLITE_CONSTRAINT_NOTNULL, @db.errcode
    assert_equal 'NOT NULL constraint failed: t2.v', @db.errmsg
  end


  def test_close_with_open_prepared_statement
    query = @db.prepare('select * from t')
    query.next
    @db.close
  end

  def test_read_only_database
    db = Extralite::Database.new(':memory:')
    db.query('create table foo (bar)')
    assert_equal false, db.read_only?

    db = Extralite::Database.new(':memory:', read_only: true)
    assert_raises(Extralite::Error) { db.query('create table foo (bar)') }
    assert_equal true, db.read_only?
  end

  def test_database_inspect
    db = Extralite::Database.new(':memory:')
    assert_match /^\#\<Extralite::Database:0x[0-9a-f]+ :memory:\>$/, db.inspect
  end

  def test_database_inspect_on_closed_database
    db = Extralite::Database.new(':memory:')
    assert_match /^\#\<Extralite::Database:0x[0-9a-f]+ :memory:\>$/, db.inspect
    db.close
    assert_match /^\#\<Extralite::Database:0x[0-9a-f]+ \(closed\)\>$/, db.inspect
  end

  def test_string_encoding
    db = Extralite::Database.new(':memory:')
    v = db.query_single_value("select 'foo'")
    assert_equal 'foo', v
    assert_equal 'UTF-8', v.encoding.name
  end

  def test_database_transaction_commit
    path = Tempfile.new('extralite_test_database_transaction_commit').path
    db1 = Extralite::Database.new(path)
    db2 = Extralite::Database.new(path)

    db1.execute('create table foo(x)')
    assert_equal ['foo'], db1.tables
    assert_equal ['foo'], db2.tables

    q1 = Queue.new
    q2 = Queue.new
    th = Thread.new do
      db1.transaction do
        assert_equal true, db1.transaction_active?
        db1.execute('insert into foo values (42)')
        q1 << true
        q2.pop
      end
      assert_equal false, db1.transaction_active?
    end
    q1.pop
    # transaction not yet committed
    assert_equal false, db2.transaction_active?
    assert_equal [], db2.query('select * from foo')

    q2 << true
    th.join
    # transaction now committed
    assert_equal [{ x: 42 }], db2.query('select * from foo')
  end

  def test_database_transaction_rollback
    db = Extralite::Database.new(':memory:')
    db.execute('create table foo(x)')

    assert_equal [], db.query('select * from foo')

    exception = nil
    begin
      db.transaction do
        db.execute('insert into foo values (42)')
        raise 'bar'
      end
    rescue => e
      exception = e
    end

    assert_equal [], db.query('select * from foo')
    assert_kind_of RuntimeError, exception
    assert_equal 'bar', exception.message
  end
end

class ScenarioTest < MiniTest::Test
  def setup
    @fn = Tempfile.new('extralite_scenario_test').path
    @db = Extralite::Database.new(@fn)
    @db.query('create table if not exists t (x,y,z)')
    @db.query('delete from t')
    @db.query('insert into t values (1, 2, 3)')
    @db.query('insert into t values (4, 5, 6)')
  end

  def test_concurrent_transactions
    done = false
    t = Thread.new do
      db = Extralite::Database.new(@fn)
      db.query 'begin immediate'
      sleep 0.01 until done

      while true
        begin
          db.query 'commit'
          break
        rescue Extralite::BusyError
          sleep 0.01
        end
      end
    end

    sleep 0.1
    @db.query 'begin deferred'
    result = @db.query_single_column('select x from t')
    assert_equal [1, 4], result

    assert_raises(Extralite::BusyError) do
      @db.query('insert into t values (7, 8, 9)')
    end

    done = true
    sleep 0.1

    assert_raises(Extralite::BusyError) do
      @db.query('insert into t values (7, 8, 9)')
    end

    assert_equal true, @db.transaction_active?

    # the thing to do in this case is to commit the read transaction, allowing
    # the other thread to commit its write transaction, and then we can
    # "upgrade" to a write transaction

    @db.query('commit')

    while true
      begin
        @db.query('begin immediate')
        break
      rescue Extralite::BusyError
        sleep 0.1
      end
    end

    @db.query('insert into t values (7, 8, 9)')
    @db.query('commit')

    result = @db.query_single_column('select x from t')
    assert_equal [1, 4, 7], result
  end

  def test_concurrent_queries
    @db.query('delete from t')
    @db.gvl_release_threshold = 1
    q1 = @db.prepare('insert into t values (?, ?, ?)')
    q2 = @db.prepare('insert into t values (?, ?, ?)')

    t1 = Thread.new do
      data = (1..50).each_slice(10).map { |a| a.map { |i| [i, i + 1, i + 2] } }
      data.each do |params|
        q1.batch_execute(params)
      end
    end

    t2 = Thread.new do
      data = (51..100).each_slice(10).map { |a| a.map { |i| [i, i + 1, i + 2] } }
      data.each do |params|
        q2.batch_execute(params)
      end
    end

    t1.join
    t2.join

    assert_equal (1..100).to_a, @db.query_single_column('select x from t order by x')
  end

  def test_database_trace
    sqls = []
    @db.trace { |sql| sqls << sql }
    GC.start

    @db.query('select 1')
    assert_equal ['select 1'], sqls

    @db.query('select 2')
    assert_equal ['select 1', 'select 2'], sqls

    query = @db.prepare('select 3')

    query.to_a
    assert_equal ['select 1', 'select 2', 'select 3'], sqls

    # turn off
    @db.trace

    query.to_a

    @db.query('select 4')
    assert_equal ['select 1', 'select 2', 'select 3'], sqls
  end
end

class BackupTest < MiniTest::Test
  def setup
    @src = Extralite::Database.new(':memory:')
    @dst = Extralite::Database.new(':memory:')

    @src.query('create table t (x,y,z)')
    @src.query('insert into t values (1, 2, 3)')
    @src.query('insert into t values (4, 5, 6)')
  end

  def test_backup
    @src.backup(@dst)
    assert_equal [[1, 2, 3], [4, 5, 6]], @dst.query_ary('select * from t')
  end

  def test_backup_with_block
    progress = []
    @src.backup(@dst) { |r, t| progress << [r, t] }
    assert_equal [[1, 2, 3], [4, 5, 6]], @dst.query_ary('select * from t')
    assert_equal [[2, 2]], progress
  end

  def test_backup_with_schema_names
    @src.backup(@dst, 'main', 'temp')
    assert_equal [[1, 2, 3], [4, 5, 6]], @dst.query_ary('select * from temp.t')
  end

  def test_backup_with_fn
    tmp_fn = Tempfile.new('extralite_test_backup_with_fn').path
    @src.backup(tmp_fn)

    db = Extralite::Database.new(tmp_fn)
    assert_equal [[1, 2, 3], [4, 5, 6]], db.query_ary('select * from t')
  end
end

class GVLReleaseThresholdTest < Minitest::Test
  def setup
    @sql = <<~SQL
      WITH RECURSIVE r(i) AS (
        VALUES(0)
        UNION ALL
        SELECT i FROM r
        LIMIT 3000000
      )
      SELECT i FROM r WHERE i = 1;
    SQL
  end

  def test_default_gvl_release_threshold
    db = Extralite::Database.new(':memory:')
    assert_equal 1000, db.gvl_release_threshold
  end

  def test_gvl_always_release
    skip if !IS_LINUX

    delays = []
    running = true
    t1 = Thread.new do
      last = Time.now
      while running
        sleep 0.1
        now = Time.now
        delays << (now - last)
        last = now
      end
    end
    t2 = Thread.new do
      db = Extralite::Database.new(':memory:')
      db.gvl_release_threshold = 1
      db.query(@sql)
    ensure
      running = false
    end
    t2.join
    t1.join

    assert delays.size > 4
    assert_equal 0, delays.select { |d| d > 0.15 }.size
  end

  def test_gvl_always_hold
    skip if !IS_LINUX

    delays = []
    running = true

    signal = Queue.new
    db = Extralite::Database.new(':memory:')
    db.gvl_release_threshold = 0

    t1 = Thread.new do
      last = Time.now
      while running
        signal << true
        sleep 0.1
        now = Time.now
        delays << (now - last)
        last = now
      end
    end

    t2 = Thread.new do
      signal.pop
      db.query(@sql)
    ensure
      running = false
    end
    t2.join
    t1.join

    assert delays.size >= 1
    assert delays.first > 0.2
  end

  def test_gvl_mode_get_set
    db = Extralite::Database.new(':memory:')
    assert_equal 1000, db.gvl_release_threshold

    db.gvl_release_threshold = 42
    assert_equal 42, db.gvl_release_threshold

    db.gvl_release_threshold = 0
    assert_equal 0, db.gvl_release_threshold

    assert_raises(ArgumentError) { db.gvl_release_threshold = :foo }

    db.gvl_release_threshold = nil
    assert_equal 1000, db.gvl_release_threshold
  end
end

class RactorTest < Minitest::Test
  def test_ractor_simple
    skip if SKIP_RACTOR_TESTS
    
    fn = Tempfile.new('extralite_test_database_in_ractor').path

    r = Ractor.new do
      path = receive
      db = Extralite::Database.new(path)
      i = receive
      db.execute 'insert into foo values (?)', i
    end

    r << fn
    db = Extralite::Database.new(fn)
    db.execute 'create table foo (x)'
    r << 42
    r.take # wait for ractor to terminate

    assert_equal 42, db.query_single_value('select x from foo')
  end

  # Adapted from here: https://github.com/sparklemotion/sqlite3-ruby/pull/365/files
  def test_ractor_share_database
    skip if SKIP_RACTOR_TESTS

    db_receiver = Ractor.new do
      db = Ractor.receive
      Ractor.yield db.object_id
      begin
        db.execute("create table foo (b)")
        raise "Should have raised an exception in db.execute()"
      rescue => e
        Ractor.yield e
      end
    end
    sleep 0.1
    db_creator = Ractor.new(db_receiver) do |db_receiver|
      db = Extralite::Database.new(":memory:")
      Ractor.yield db.object_id
      db_receiver.send(db)
      sleep 0.1
      db.execute("create table foo (a)")
    end
    first_oid = db_creator.take
    second_oid = db_receiver.take
    refute_equal first_oid, second_oid
    ex = db_receiver.take
    assert_kind_of Extralite::Error, ex
    assert_equal "Database is closed", ex.message
  end

  STRESS_DB_NAME = Tempfile.new('extralite_test_ractor_stress').path

  # Adapted from here: https://github.com/sparklemotion/sqlite3-ruby/pull/365/files
  def test_ractor_stress
    skip if SKIP_RACTOR_TESTS
    
    Ractor.make_shareable(STRESS_DB_NAME)

    db = Extralite::Database.new(STRESS_DB_NAME)
    db.execute("PRAGMA journal_mode=WAL") # A little slow without this
    db.execute("create table stress_test (a integer primary_key, b text)")
    random = Random.new.freeze
    ractors = (0..9).map do |ractor_number|
      Ractor.new(random, ractor_number) do |random, ractor_number|
        db_in_ractor = Extralite::Database.new(STRESS_DB_NAME)
        db_in_ractor.busy_timeout = 3
        10.times do |i|
          db_in_ractor.execute("insert into stress_test(a, b) values (#{ractor_number * 100 + i}, '#{random.rand}')")
        end
      end
    end
    ractors.each { |r| r.take }
    final_check = Ractor.new do
      db_in_ractor = Extralite::Database.new(STRESS_DB_NAME)
      count = db_in_ractor.query_single_value("select count(*) from stress_test")
      Ractor.yield count
    end
    count = final_check.take
    assert_equal 100, count
  end
end
