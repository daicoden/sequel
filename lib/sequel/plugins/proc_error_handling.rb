module Sequel
  module Plugins
    
    module ProcErrorHandling
      def self.apply(model)
        model.class_eval do
          alias peh_orig_update        update
          alias peh_orig_update_all    update_all
          alias peh_orig_update_except update_except
          alias peh_orig_update_only   update_only
          alias peh_orig_initialize    initialize
          alias peh_orig_save          save

          class << self
            alias peh_orig_create create

            def on_error(&block)
              @error_block = block
            end

            def peh_error_occured(model)
              if @error_block
                @error_block.call(model)
              elsif superclass.respond_to? :peh_error_occured
                superclass.peh_error_occured(model)
              end
            end
          end
        end
      end

      def self.configure(model,&block)
      end
      
      module InstanceMethods
        def update(hash,*error_proc)
          peh_orig_update(hash)
        rescue
          result = PEH.send(:process_error_proc,error_proc,self,hash)
          retry if result == :retry
          result
        end

        def update_all(hash, *error_proc)
          peh_orig_update_all(hash)
         rescue
          result = PEH.send(:process_error_proc,error_proc,self,hash)
          retry if result == :retry
          result
        end

        def update_except(hash, *except)
          error_procs = []
          error_procs.unshift except.pop while except.last.is_a? Proc

          # Only want to retry the update, don't want to clear error_procs
          begin
            peh_orig_update_except(hash,*except)
          rescue
            result = PEH.send(:process_error_proc,error_procs,self,hash)
            retry if result == :retry
            result
          end
        end

        def update_only(hash, *only)
          error_procs = []
          error_procs.unshift only.pop while only.last.is_a? Proc

          begin
            peh_orig_update_only(hash,*only)
          rescue
            result = PEH.send(:process_error_proc,error_procs,self,hash)
            retry if result == :retry
            result
          end
        end

        def initialize(values = {}, *args,&block)
          orig = args.dup
          error_procs = []
          error_procs.unshift args.pop while args.last.is_a? Proc
          from_db = args.pop || false # First value will be nil or boolean
          raise ArgumentError, 
            "Invalid Arguments passed to #new #{orig.inpsect}" unless args.empty?

          begin
            peh_orig_initialize(values,from_db,&block)
          rescue
            result = PEH.send(:process_error_proc,error_procs,self,values)
            retry if result == :retry
            # Special for new since we can't return anything else
            if result.is_a? self.class
              values  = result.values
              from_db = true unless result.new?
              retry
            end
            # Should not get here... means result was something other
            # then :raise, :retry, nil, or an instance of self.class
            raise "#new can not return any other object, there is" <<
            " an error in your PEH proc"
          end
        end

        def save(*columns)
          error_procs = []
          error_procs.unshift columns.pop while columns.last.is_a? Proc

          begin
            peh_orig_save(*columns)
          rescue
            result = PEH.send(:process_error_proc,error_procs,self,values)
            retry if result == :retry
            result
          end
        end

      end

      module ClassMethods
        def create(values = {}, *error_proc, &block)
          new(values,*error_proc, &block).save *error_proc
        end
      end

      module DatasetMethods
      end

      def self.process_error_proc(procs,obj,hash)
        klass = obj.class
        # if procs is nil then compact array and result will be nil
        # if procs is single proc wrap in array so code runs normaly
        # if procs is array execute each one till value returned
        procs = [procs].compact unless procs.is_a? Array
        result = procs.each do |ep|
          val = ep.call(klass,hash) 
          break val unless val.nil? 
        end
        # if result is the original array then error handling failed
        result = (result == procs) ? nil : result

        if result == :raise or result.nil?
          klass.peh_error_occured(obj)
          raise $!
        end
        if result != nil and result != :retry and result.class != obj.class
          raise Sequel::Error, "An error handling proc must return either " <<
          "nil, :raise, :retry, or an instance of the klass it is rescuing."
        end
        result
      end

      private_class_method :process_error_proc
    end

    PEH = ProcErrorHandling
  end
end
