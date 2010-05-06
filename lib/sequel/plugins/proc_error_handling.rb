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
          class << self
            alias peh_orig_create create
          end
        end
      end

      def self.configure(model,&block)
      end
      
      module InstanceMethods
      end

      module ClassMethods
        def create(values = {}, error_proc = nil, &block)
          peh_orig_create(values,&block)
        rescue 
          raise $! unless error_proc
          result = PEH.send(:process_error_proc,error_proc,self,values)
          raise $! if result == :raise or result.nil?
          retry if result == :retry
          result
        end
      end

      module DatasetMethods
      end

      def self.process_error_proc(procs,*proc_vals)
        procs = [procs] unless procs.is_a? Array
        result = procs.each do |ep|
          val = ep.call(*proc_vals) 
          break val unless val.nil? 
        end
        # if result is the original array then error handling failed
        (result == procs) ? nil : result
      end

      private_class_method :process_error_proc
    end

    PEH = ProcErrorHandling
  end
end
