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
        def create(values = {}, &block)
          orig_create(values,&block)
        end
      end

      module DatasetMethods
      end
    end

    PEH = ProcErrorHandling
  end
end
