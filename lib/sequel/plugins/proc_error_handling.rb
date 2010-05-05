module Sequel
  module Plugins
    module ProcErrorHandling
      def self.apply(model)
        model.class_eval do
          class << self
            alias orig_create create
          end
        end
      end

      def self.configure(model,&block)
      end
      
      module InstanceMethods
      end

      module ClassMethods
        def create(values = {}, error_proc = nil, &block)
          orig_create(values,&block)
        rescue 
          raise $! unless error_proc
          result = error_proc.call(self.class,values) 
          raise $! if result == :raise or !result
          retry if result == :retry
          result
        end
      end

      module DatasetMethods
      end
    end

    PEH = ProcErrorHandling
  end
end
