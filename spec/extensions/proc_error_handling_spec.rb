require File.join(File.dirname(__FILE__), "spec_helper")

describe "Sequel::Plugins::ProcErrorHandling" do
  before(:each) do
    @db = db = MODEL_DB.clone
    def db.schema(table,opts={})
      { 
        foos: [
          [ :id,       type: :integer, primary_key: true ],
          [ :value,    type: :string                     ],
          [ :unique,   type: :string                     ],
          [ :required, type: :string                     ]
        ] 
      }[table]
    end

    def db.dataset(*args)
      ds = super(*args)
      def ds.columns
        {
          [:foos] => [:id, :value, :unique, :required]
        }[opts[:from] + (opts[:join] || []).map { |x| x.table }]
      end
      ds
    end

    class ::Foo < Sequel::Model(db)
      def validate
        errors.add(:required, "is required.")  unless required
        errors.add(:unique, "must be unique.") if 
          self.class.first("unique = ?",unique)
      end
    end
    @c = ::Foo
    @c.plugin :proc_error_handling

    def valid_attributes
      {
        value:    'value', 
        unique:   "unique#{Foo.count}",
        required: 'required'
      }
    end
    @ds = Foo.dataset
    @db.reset

  end

  after(:each) do
    Object.send(:remove_const, :Foo)
  end 
  
  it "should implement the plugin framework" do
    Sequel::Plugins::PEH.should respond_to(:apply)
    Sequel::Plugins::PEH.should respond_to(:configure)

    defined?(Sequel::Plugins::PEH::InstanceMethods).should eql("constant")
    defined?(Sequel::Plugins::PEH::ClassMethods).should eql("constant")
    defined?(Sequel::Plugins::PEH::DatasetMethods).should eql("constant")
  end

  it "should function normaly for #create" do

    def @ds.fetch_rows(sql)
      return if sql == "SELECT * FROM foos WHERE (unique = 'unique0') LIMIT 1"
      yield({:count => 0}) and return if sql == "SELECT COUNT(*) AS count FROM foos LIMIT 1"
      yield({:id => 1})
    end

    attrs = valid_attributes
    @c.create(attrs).should be_an_instance_of(@c)
    @db.sqls.should == ["INSERT INTO foos (value, unique, required) VALUES ('value', 'unique0', 'required')"]


   def @ds.fetch_rows(sql)
     case sql
     when "SELECT * FROM foos WHERE (unique = 'unique0') LIMIT 1"
       yield({:id => 1}) 
     when "SELECT COUNT(*) AS count FROM foos LIMIT 1"
       yield({:count => 1}) 
     when "INSERT INTO foos (value, unique, required) VALUES ('value', 'unique1', 'required')"
      yield({:id => 2}) 
     when "SELECT * FROM foos WHERE (unique = 'unique1') LIMIT 1"
     else
       yield({:id => 2})
     end
    end

    # Unique Failure
    bad_attrs = attrs.dup
    lambda { @c.create(bad_attrs) }.should raise_error Sequel::ValidationFailed
    attrs = valid_attributes
    @c.create(attrs).should be_an_instance_of(@c)
    @db.sqls.last.should == "INSERT INTO foos (value, unique, required) VALUES ('value', 'unique1', 'required')"

    #Required Failure
    bad_attrs = valid_attributes
    bad_attrs.delete(:required)
    lambda { @c.create(bad_attrs) }.should raise_error Sequel::ValidationFailed

  end

  it "should handle the errors for #create if proc given" do
    unique_handle = proc do |klass,values| 
      if $!.message =~ /must be unique./ 
        klass.first("unique = ?", values[:unique])
      end
    end

   def @ds.fetch_rows(sql)
     case sql
     when "SELECT * FROM foos WHERE (unique = 'unique0') LIMIT 1"
       yield({:id => 1}) 
     when "SELECT COUNT(*) AS count FROM foos LIMIT 1"
      yield({:count => 0}) 
     end
   end

   # Bad attrs because DB is returning a unique model
   bad_attrs = valid_attributes
   lambda { @c.create(bad_attrs) }.should raise_error Sequel::ValidationFailed
   @c.create(bad_attrs,unique_handle).should be_an_instance_of(@c)

  end

end
