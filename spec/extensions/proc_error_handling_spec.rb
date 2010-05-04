require File.join(File.dirname(__FILE__), "spec_helper")

describe "Sequel::Plugins::ProcErrorHandling" do
  before(:all) do
    @db = db = MODEL_DB.clone
    def db.schema(table,opts={})
      { 
        foos: [
          [ :id,    primary_key: true, type: :integer],
          [ :value, type: :string                    ]
        ] 
      }[table]
    end
    class Foo < Sequel::Model(db)
    end
    @c = Foo
    @c.plugin :proc_error_handling
    @m = @c.new
  end
   
  it "should implement the plugin framework" do
    Sequel::Plugins::PEH.should respond_to(:apply)
    Sequel::Plugins::PEH.should respond_to(:configure)

    defined?(Sequel::Plugins::PEH::InstanceMethods).should eql("constant")
    defined?(Sequel::Plugins::PEH::ClassMethods).should eql("constant")
    defined?(Sequel::Plugins::PEH::DatasetMethods).should eql("constant")
  end

  it "should provide PEH for #create" do
    @c.create(:value => 3)
  end

end
