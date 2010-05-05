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

      def ds.insert(*args)
        db << insert_sql(*args)
        1
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

    def valid_attributes(klass)
      {
        value:    'value', 
        unique:   "unique#{klass.count}",
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
    p @ds
    attrs = valid_attributes(@c)
    @c.create(attrs).should be_an_instance_of(@c)
    p ::Foo.first.required

    bad_attrs = valid_attributes(@c).dup
    bad_attrs.delete(:required)
    lambda { @c.create(bad_attrs) }.should raise_error
  end

end
