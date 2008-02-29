###############################################################################
#
# DBD::SQLite - a DBD for SQLite for versions < 3
#
# Uses Jamis Buck's 'sqlite-ruby' driver to interface with SQLite directly
#
# (c) 2008 Erik Hollensbe & Christopher Maujean.
#
################################################################################

begin
    require 'rubygems'
    gem 'sqlite'
rescue Exception => e
end

require 'sqlite'

module DBI
    module DBD
        class SQLite

            USED_DBD_VERSION = "0.1"

            # XXX I'm starting to think this is less of a problem with SQLite
            # and more with the old C DBD
            def self.check_sql(sql)
                raise DBI::DatabaseError, "Bad SQL: SQL cannot contain nulls" if sql =~ /\0/
            end

            class Driver < DBI::BaseDriver
                def initialize
                    super USED_DBD_VERSION
                end

                def connect(dbname, user, auth, attr_hash)
                    return Database.new(dbname, user, auth, attr_hash)
                end
            end

            class Database < DBI::BaseDatabase
                include DBI::SQL::BasicBind

                attr_reader :db

                def initialize(dbname, user, auth, attr_hash)
                    # FIXME why isn't this crap being done in DBI?
                    unless dbname.kind_of? String
                        raise DBI::InterfaceError, "Database Name must be a string"
                    end

                    unless dbname.length > 0
                        raise DBI::InterfaceError, "Database Name needs to be length > 0"
                    end

                    unless attr_hash.kind_of? Hash
                        raise DBI::InterfaceError, "Attributes should be a hash"
                    end

                    # FIXME handle busy_timeout in SQLite driver
                    @autocommit = false
                    @autocommit = true        if attr_hash["AutoCommit"]

                    # open the database
                    begin
                        @db = ::SQLite::Database.new(dbname)
                    rescue Exception => e
                        raise DBI::OperationalError, "Couldn't open database #{dbname}: #{e.message}"
                    end
                end

                def disconnect
                    @db.close if @db and !@db.closed?
                    @db = nil
                end

                def prepare(stmt)
                    return Statement.new(stmt, self)
                end

                def ping
                    return !@db.closed?
                end

                def do(stmt, *bindvars)

                    # FIXME this *should* be building a statement handle and doing it that way.

                end

                def tables
                    # select name from sqlite_master where type='table';
                    # XXX does sqlite use views too? not sure, but they need to be included according to spec
                end

                def commit
                    # if autocommit is 0
                        # end the current transaction and start a new one.
                        # raise a DBI::DatabaseError if we fail it
                    # if autocommit is 1
                        # warn that commit is ineffective while AutoCommit is on.

                    # return nil
                end

                def rollback
                    # if autocommit is 0
                        # rollback the current transaction and start a new one
                        # raise a DBI::DatabaseError if we fail it
                    # if autocommit is 1
                        # warn that rollback is ineffective while AutoCommit is on

                    # return nil
                end

                def [](key)
                    # check the key to ensure it's a string

                    # if the key is non-nil:
                        # if requested, coerce the autocommit value to true/false FIXME not sure if this is the best idea
                        # if requested, coerce sqlite_full_column_names to t/f FIXME not even sure if this is necessary.
                    # else return nil

                    # XXX this whole routine might be pointless.
                end

                def []=(key, value)
                    # check the key to ensure it's a string
                    
                    # if our key is AutoCommit
                    # and our value is true
                        # turn AutoCommit on
                        # immediately commit the transaction XXX I think this is a *horrible* handling of this. 
                        # raise a DBI::DatabaseError if this fails
                    # else, if our value is false 
                        # start a transaction
                        # raise a DBI::DatabaseError if this fails 

                    # if our key is "sqlite_full_column_names"
                    # FIXME jesus, this does nothing but toggle the value... I still can't find a place where this actually affects the library.
                end

                def columns(tablename)
                    # execute PRAGMA table_info(tablename)
                    # fill out the name, type_name, nullable, and default entries in an hash which is a part of array 
                    # XXX it'd be nice if the spec was changed to do this k/v with the name as the key.
                end
            end

            class Statement < DBI::BaseStatement
                include DBI::SQL::BasicBind
                include DBI::SQL::BasicQuote

                #
                # NOTE these three constants are taken directly out of the old
                #      SQLite.c. Not sure of its utility yet.
                #

                TYPE_CONV_MAP = 
                    [                                                                     
                        [ /^INT(EGER)?$/i,            proc {|str, c| c.as_int(str) } ],     
                        [ /^(OID|ROWID|_ROWID_)$/i,   proc {|str, c| c.as_int(str) }],      
                        [ /^(FLOAT|REAL|DOUBLE)$/i,   proc {|str, c| c.as_float(str) }],    
                        [ /^DECIMAL/i,                proc {|str, c| c.as_float(str) }],    
                        [ /^(BOOL|BOOLEAN)$/i,        proc {|str, c| c.as_bool(str) }],     
                        [ /^TIME$/i,                  proc {|str, c| c.as_time(str) }],     
                        [ /^DATE$/i,                  proc {|str, c| c.as_date(str) }],     
                        [ /^TIMESTAMP$/i,             proc {|str, c| c.as_timestamp(str) }] 
                        # [ /^(VARCHAR|CHAR|TEXT)/i,    proc {|str, c| c.as_str(str).dup } ]  
                    ]                                                                     

                CONVERTER = DBI::SQL::BasicQuote::Coerce.new

                # FIXME this definitely needs to be a private method
                CONVERTER_PROC = proc do |tm, cv, val, typ|
                    ret = val.dup             
                    tm.each do |reg, pr|      
                        if typ =~ reg           
                            ret = pr.call(val, cv)
                            break                 
                        end                     
                    end                       
                    ret                       
                end

                def initialize(stmt, dbh)
                    @dbh       = dbh
                    @statement = DBI::SQL::PreparedStatement.new(@dbh, stmt)
                    @attr      = { }
                    @params    = [ ]
                    @rows      = [ ]
                    @result_set = nil
                end

                def bind_param(param, value, attributes=nil)
                    unless param.kind_of? Fixnum
                        raise DBI::InterfaceError, "Only numeric parameters are supported"
                    end

                    @params[param-1] = value

                    # FIXME what to do with attributes? are they important in SQLite?
                end

                def execute
                    # FIXME find out what attrs we need to support and how we support them.
                    sql = @statement.bind(@params)
                    ::DBI::DBD::SQLite.check_sql(sql)
                   
                    begin
                        # XXX this is not AutoCommit-aware yet
                        @dbh.db.transaction
                        @result_set = @dbh.db.query(sql)
                        @dbh.db.commit
                    rescue Exception => e
                        raise DBI::DatabaseError, e.message
                    end
                end
                
                def cancel
                    # this should probably rollback the transaction?
                end

                def finish
                    # this should probably:
                    # close the transactions (what's the spec say here?)
                    # nil out the result set
                    @result_set.close if @result_set
                    @result_set = nil
                end

                def fetch
                    # fetch each row 
                    # if we have a result, convert it using the TYPE_CONV_MAP
                    # stuff it into @rows. XXX I really think this is a bad idea. 
                end

                def fetch_scroll(direction, offset)
                    # XXX this method is so poorly implemented it's disgusting. Replace completely.
                end

                def column_info
                    @result_set.columns
                end

                def rows
                    raise "Not implemented yet"
                end

                def quote(obj)
                    # special (read: stupid) handling for Timestamps
                    # otherwise call quote in the superclass
                end
            end
        end
    end
end
