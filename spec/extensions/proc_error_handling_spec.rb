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

    ::GET_BY_UNIQUE0      = 
      "SELECT * FROM foos WHERE (unique = 'unique0') LIMIT 1" unless
      defined? ::GET_BY_UNIQUE0
    ::GET_BY_UNIQUE1      = 
      "SELECT * FROM foos WHERE (unique = 'unique1') LIMIT 1" unless
      defined? ::GET_BY_UNIQUE1
    ::GET_FOO_COUNT       = 
      "SELECT COUNT(*) AS count FROM foos LIMIT 1" unless
      defined? ::GET_FOO_COUNT
    ::INSERT_VALID_ATTRS0 = "INSERT INTO foos (value, unique, required) " <<
      "VALUES ('value', 'unique0', 'required')" unless
      defined? ::INSERT_VALID_ATTRS0
    ::INSERT_VALID_ATTRS1 = "INSERT INTO foos (value, unique, required) " <<
      "VALUES ('value', 'unique1', 'required')" unless
      defined? ::INSERT_VALID_ATTRS1

    def define_virgin_dataset(ds)
      def ds.fetch_rows(sql)
        case sql
        when GET_BY_UNIQUE0
          #nop
        when GET_FOO_COUNT
          yield({:count => 0}) 
        when INSERT_VALID_ATTRS0
          yield({:id => 1, 
                :value => 'value', 
                :unique => 'unique0', 
                :required => 'required'}) 
        else
          yield({:id => 1, 
                :value => 'value', 
                :unique => 'unique0', 
                :required => 'required'}) 
        end
      end
    end

    def define_one_record_dataset(ds)
      def ds.fetch_rows(sql)
        case sql
        when GET_BY_UNIQUE0
          yield({:id => 1, :value => 'value', 
                :unique => 'unique0', 
                :required => 'required'}) 
        when GET_FOO_COUNT
          yield({:count => 1}) 
        when INSERT_VALID_ATTRS1
          yield({:id => 2, :value => 'value', 
                :unique => 'unique1', 
                :required => 'required'}) 
        when GET_BY_UNIQUE1
        else
          yield({:id => 2, :value => 'value', 
                :unique => 'unique1', 
                :required => 'required'}) 
        end
      end
    end

    def unique_handle 
      proc do |klass,values| 
        if $!.message =~ /must be unique./ 
          record = klass.first("unique = ?", values[:unique])
          record if record.required == values[:required] and 
            record.value == values[:value]
        end
      end
    end

    def required_handle 
      proc do |klass, values|
        unless values[:required]
          values[:required] = 'required'
          :retry
        end
      end
    end

    def false_on_error
      proc { |klass, values| false }
    end
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

  describe "a proc error handler", :shared => true do
    it "should return result of the error proc" do
      define_one_record_dataset(@ds)

      # Bad attrs because DB is returning a unique model
      bad_attrs = valid_attributes.merge :unique => 'unique0'
      args = [ bad_attrs.dup, *@peh_args ]
      lambda{ @peh_base.send(@peh_method, *args) }.should(
        raise_error Sequel::ValidationFailed
      )
      args = [ bad_attrs.dup, *@peh_args ]
      @peh_base.send(@peh_method,*args,false_on_error).should be false
    end

    it "should pass error if error not handled" do
      define_virgin_dataset(@ds)

      bad_attrs = valid_attributes.delete_if { |k,v| k == :required }
      args = [ bad_attrs.dup, *@peh_args ]
      lambda{ @peh_base.send(@peh_method, *args,unique_handle) }.should(
        raise_error Sequel::ValidationFailed
      )
    end

    it "should retry DB transaction if specified by block" do
      define_virgin_dataset(@ds)
      
      bad_attrs = valid_attributes.delete_if { |k,v| k == :required }
      args = [ bad_attrs.dup, *@peh_args ]
      lambda{ @peh_base.send(@peh_method, *args) }.should(
        raise_error Sequel::ValidationFailed
      )

      args = [ bad_attrs.dup, *@peh_args ]
      @peh_base.send(@peh_method, *args,required_handle).
        should be_an_instance_of @c
    end

    it "should take an array of error procs to handle multiple items" do
      define_one_record_dataset(@ds)

      bad_attrs = valid_attributes.merge(:unique => 'unique0').
        delete_if { |k,v| k == :required }

      args = [ bad_attrs.dup, *@peh_args ]
      lambda{ @peh_base.send(@peh_method, *args) }.
        should raise_error(Sequel::ValidationFailed)
     
      args = [ bad_attrs.dup, *@peh_args ]
      lambda{ @peh_base.send(@peh_method, *args,unique_handle) }.
        should raise_error(Sequel::ValidationFailed)
      
      args = [ bad_attrs.dup, *@peh_args ]
      lambda{ @peh_base.send(@peh_method, *args,required_handle) }.
        should raise_error(Sequel::ValidationFailed)

      args = [ bad_attrs.dup, *@peh_args ]
      @peh_base.send(@peh_method, *args,[unique_handle,required_handle]).
        should be_an_instance_of(@c)
    end

    it "should raise an error regardless of other handlers if :raise " <<
       "returned in a block" do
      define_virgin_dataset(@ds)
      bad_attrs = valid_attributes
      bad_attrs[:required] = nil
      base1 = (@peh_base == @c) ? @c : @peh_base.dup
      base2 = (@peh_base == @c) ? @c : @peh_base.dup
      base3 = (@peh_base == @c) ? @c : @peh_base.dup
         
      args = [ bad_attrs.dup, *@peh_args ]
      base1.send(@peh_method, *args,required_handle).
        should be_an_instance_of(@c)

      args = [ bad_attrs.dup, *@peh_args ]
      base2.send(@peh_method, *args,[required_handle, proc{:raise}]).
        should be_an_instance_of(@c)

      args = [ bad_attrs.dup, *@peh_args ]
      lambda{base3.send(@peh_method, *args, [proc{:raise},required_handle])}.
        should raise_error Sequel::ValidationFailed
    end

    it "should execute specified block on error" do
      error_model = nil
      @c.on_error{ |m| @error_model = m}

      define_one_record_dataset(@ds)
      bad_attrs = valid_attributes.merge :unique => 'unique0'

      args = [ bad_attrs.dup, *@peh_args ]
      lambda{
        @peh_base.send(@peh_method,*args)
      }.should raise_error Sequel::ValidationFailed

      @error_model.should be_an_instance_of(@c)
    end

    it "should run the error block of a superclass if no block given" do
      begin
        class ::Bar < Foo
          def validate
            errors.add(:unique, "must be unique.") if 
              self.class.first("unique = ?",unique)
          end
        end
        Bar.plugin :proc_error_handling

        Foo.on_error{ |m| @error_model = m}

        @peh_base = (@peh_base == @c) ? Bar : Bar.new

        define_one_record_dataset(@ds)
        bad_attrs = valid_attributes.merge :unique => 'unique0'

        args = [ bad_attrs.dup, *@peh_args ]
        lambda{
          @peh_base.send(@peh_method,*args)
        }.should raise_error Sequel::ValidationFailed

        @error_model.should be_an_instance_of(Bar)
      ensure
        Object.send(:remove_const, :Bar)
      end
    end

  end

  describe "(#create)" do
    before(:each) do
      @peh_base   = @c
      @peh_method = :create
      @peh_args   = []
    end

    it "should function normaly with no error handling" do
      # Inserting a new record in virgin tabel
      define_virgin_dataset(@ds)

      attrs = valid_attributes
      @c.create(attrs).should be_an_instance_of(@c)
      @db.sqls.last.should eql INSERT_VALID_ATTRS0 
      @db.reset

      #mock of dataset with 1 record of id 1
      define_one_record_dataset(@ds)

      # Unique Failure
      bad_attrs = attrs.dup
      lambda{ @c.create(bad_attrs.dup) }.should(
        raise_error(Sequel::ValidationFailed)
      )
      attrs = valid_attributes
      @c.create(attrs).should be_an_instance_of(@c)
      @db.sqls.last.should eql INSERT_VALID_ATTRS1
      @db.reset

      #Required Failure
      bad_attrs = valid_attributes.delete_if { |k,v| k == :required }
      lambda{@c.create(bad_attrs.dup)}.should raise_error Sequel::ValidationFailed
      @db.reset

      @c.create(bad_attrs.dup) { |m| m.required = 'required' }
      @db.sqls.last.should eql INSERT_VALID_ATTRS1
    end

    it_should_behave_like "a proc error handler"

  end

  describe "(#update)" do
    before(:each) do
      @peh_base = @c.new
      @peh_method = :update 
      @peh_args   = []
    end

    it_should_behave_like "a proc error handler"
  end

  describe "(#update_all)" do
    before(:each) do 
      @peh_base   = @c.new
      @peh_method = :update_all
      @peh_args   = []
    end

    it_should_behave_like "a proc error handler"
  end

  describe "(#update_except)" do
    before(:each) do 
      @peh_base   = @c.new 
      @peh_method = :update_except
      @peh_args   =  [:a_column]
    end 

    it_should_behave_like "a proc error handler"
  end

  describe "(#update_except)" do
    before(:each) do 
      @peh_base   = @c.new 
      @peh_method = :update_only
      @peh_args   =  [:value, :required, :unique]
    end 

    it_should_behave_like "a proc error handler"
  end
end
