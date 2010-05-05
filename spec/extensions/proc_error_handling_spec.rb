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

      def to_hash
        {
          id:       id,
          value:    value,
          unique:   unique,
          required: required
        }
      end

      def self.new_from_sql(params)
        model = self.new
        params.each { |k,v| model.send("#{k}=",v) }
        model
      end
    end
    @c = ::Foo
    @c.plugin :proc_error_handling

    def valid_attributes(klass)
      {
        value:    'value', 
        unique:   "unique",#{klass.count}",
        required: 'required'
      }
    end
    @ds = Foo.dataset
    @db.reset

    def @ds.fetch_rows(sql)
      @db.execute(sql)

      results = if sql =~ /SELECT \* FROM foos/ 
        s = sql
        while s =~ /SELECT \* FROM foos WHERE (\(.*?\))/
          s = $1
        end

        if s != "SELECT * FROM foos"
          conditions =  s.gsub(/\(|\)/,'').split(/ AND /)
          conditions.map do |condition|
            @foos.find_from_condition(*condition.split(/ = /))
          end.flatten.uniq
        else
          @foos
        end
      end

      return if !results or results.empty?
      
      results.each { |r| yield(r.to_hash) unless r.nil? }
    end

    def @ds.insert(*args)
      @foos << Foo.new_from_sql(*args)
      @db.execute insert_sql(*args)
    end

    @ds.instance_eval do
      @foos = []
      @foos.instance_eval do
        def find_from_condition(prop,value)
          self.map do |foo|
            foo if foo.send(prop.to_sym).to_s == value.gsub("'",'')
          end.flatten
        end
      end

      def disect_sql(sql)
        sql.scan(/\(.*\)/)
        p sql.scan(/(\(.*\))?/)
      end
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

  it "should function normaly for #create" do
    attrs = valid_attributes(@c)
    @c.create(attrs).should be_an_instance_of(@c)

    bad_attrs = valid_attributes(@c).dup
    lambda { @c.create(bad_attrs) }.should raise_error Sequel::ValidationFailed
    bad_attrs[:unique] = "new_unique"
    @c.create(bad_attrs).should be_an_instance_of(@c)

    bad_attrs[:unique] = "new_unique2"
    bad_attrs.delete(:required)
    lambda { @c.create(bad_attrs) }.should raise_error Sequel::ValidationFailed

  end

end
