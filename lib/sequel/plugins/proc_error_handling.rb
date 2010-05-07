module Sequel
  module Plugins
    # Methodologies
    #
    # Practically it is best if you return a modified model.
    # If you want to return false or some other variable then you
    # will have to put in checks in the control code.  The whole
    # point of the proc error handling is to provide correction code
    # to allow the control code to function normaly.  Anything else
    # and the code should enter the exceptional code.
    #
    # #new is enforced this way since it can only return an instance
    # of itself.  In the future #create, #update, #set may be modified
    # so that only a model, :retry, :raise, or nil may be returned
    module ProcErrorHandling
      def self.apply(model)
        model.class_eval do
          alias peh_orig_update        update
          alias peh_orig_update_all    update_all
          alias peh_orig_update_except update_except
          alias peh_orig_update_only   update_only

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
        def update(hash,error_proc = nil)
          peh_orig_update(hash)
        rescue
          result = PEH.send(:process_error_proc,error_proc,self,hash)
          retry if result == :retry
          result
        end

        def update_all(hash, error_proc = nil)
          peh_orig_update_all(hash)
         rescue
          result = PEH.send(:process_error_proc,error_proc,self,hash)
          retry if result == :retry
          result
        end

        def update_except(hash, *except)
          error_proc = nil unless defined? error_proc
          *except, error_proc = *except if except.last.is_a? Proc or 
            except.last.is_a? Array

          peh_orig_update_except(hash,*except)
        rescue
          result = PEH.send(:process_error_proc,error_proc,self,hash)
          retry if result == :retry
          result
        end

        def update_only(hash, *only)
          error_proc = nil unless defined? error_proc
          *only, error_proc = *only if only.last.is_a? Proc or 
            only.last.is_a? Array
          peh_orig_update_only(hash,*only)
        rescue
          result = PEH.send(:process_error_proc,error_proc,self,hash)
          retry if result == :retry
          result
        end

      end

      module ClassMethods
        def create(values = {}, error_proc = nil, &block)
          # Because we need to catch where the error occured we need
          # to split this up into 3 parts.
          # in the future we could just modify initialize to take
          # error handling blocks and have that handel the errors instead
          # of create.
          #
          # We can't do this now because initilize can not return
          # anything else besides an instance of the object.  Create
          # on the other hand is currently speced to return the result
          # of the error proc.  I am leaning twoards not allowing this
          # and saying you eithir have to return :raise, :retry, or nil
          # This would enforce the methodology of providing error
          # handling with the purpose of massaging the bad input
          # into acceptable input
          model = nil
          model = new(values,&block)
          model.save
        rescue 
          result = PEH.send(:process_error_proc, 
                            error_proc, 
                            model || self.new, 
                            values)
          retry if result == :retry
          result
        end
      end

      module DatasetMethods
      end

      def self.process_error_proc(procs,obj,hash)
        klass = (obj.is_a? Class) ? obj : obj.class
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
        result
      end

      private_class_method :process_error_proc
    end

    PEH = ProcErrorHandling
  end
end
