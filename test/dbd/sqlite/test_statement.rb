require 'test/unit'
require 'fileutils'

class TestStatement < Test::Unit::TestCase
    def test_constructor
        sth = DBI::DBD::SQLite::Statement.new("select * from foo", @dbh.instance_variable_get("@handle"))

        assert_kind_of DBI::DBD::SQLite::Statement, sth
        assert sth.instance_variable_get("@dbh")
        assert_kind_of DBI::DBD::SQLite::Database, sth.instance_variable_get("@dbh")
        assert_equal(@dbh.instance_variable_get("@handle"), sth.instance_variable_get("@dbh"))
        assert_kind_of DBI::SQL::PreparedStatement, sth.instance_variable_get("@statement")
        assert_equal({ }, sth.instance_variable_get("@attr"))
        assert_equal([ ], sth.instance_variable_get("@params"))
        assert_nil(sth.instance_variable_get("@result_set"))
        assert_equal([ ], sth.instance_variable_get("@rows"))

        sth = @dbh.prepare("select * from foo")

        assert_kind_of DBI::StatementHandle, sth
    end

    def test_bind_param
        sth = DBI::DBD::SQLite::Statement.new("select * from foo", @dbh.instance_variable_get("@handle"))

        assert_raise(DBI::InterfaceError) do
            sth.bind_param(:foo, "monkeys")
        end

        for test_sth in [sth, @dbh.prepare("select * from foo")] do
            test_sth.bind_param(1, "monkeys", nil)

            params = test_sth.instance_variable_get("@params") || test_sth.instance_variable_get("@handle").instance_variable_get("@params")

            assert_equal "monkeys", params[0]

            # set a bunch of stuff.
            %w(I like monkeys).each_with_index { |x, i| test_sth.bind_param(i+1, x) }

            params = test_sth.instance_variable_get("@params") || test_sth.instance_variable_get("@handle").instance_variable_get("@params")
            
            assert_equal %w(I like monkeys), params

            # FIXME what to do with attributes? are they important in SQLite?
        end
    end

    def test_execute
        assert_nothing_raised do 
            sth = @dbh.prepare("select * from names")
            sth.execute
            sth.finish
        end

        assert_nothing_raised do
            sth = @dbh.prepare("select * from names where name = ?")
            sth.execute("Bob")
            sth.finish
        end

        assert_nothing_raised do
            sth = @dbh.prepare("insert into names (name, age) values (?, ?)")
            sth.execute("Bill", 22);
            sth.finish
        end
    end

    def setup
        config = DBDConfig.get_config['sqlite']

        system("sqlite #{config['dbname']} < dbd/sqlite/up.sql");

        # this will not be used in all tests
        @dbh = DBI.connect('dbi:SQLite:'+config['dbname'], nil, nil, { }) 
    end

    def teardown
        # XXX obviously, this comes with its problems as some of this is being
        # tested here.
        @dbh.disconnect if @dbh.connected?
        config = DBDConfig.get_config['sqlite']
        FileUtils.rm_f(config['dbname'])
    end
end
