# encoding: UTF-8

module Spontaneous::Plugins
  module SchemaHierarchy

    module ClassMethods
      def schema_validate
        if schema_id.nil?
          Spontaneous::Schema.missing_id!(self)
        else
          # only need to check internal consistency if class already existed
          fields.each do |field|
            if field.schema_id.nil?
              Spontaneous::Schema.missing_id!(self, :field, field)
            end
          end
          # boxes don't have boxes
          if respond_to?(:boxes)
            boxes.each do |box|
              if box.schema_id.nil?
                Spontaneous::Schema.missing_id!(self, :box, box)
              end
            end
          end

          styles.each do |style|
            if style.schema_id.nil?
              Spontaneous::Schema.missing_id!(self, :style, style)
            end
          end
          if respond_to?(:layouts)
            layouts.each do |layout|
              if layout.schema_id.nil?
                Spontaneous::Schema.missing_id!(self, :layout, layout)
              end
            end
          end
        end
      end

      def subclasses
        @subclasses ||= []
      end

      # supertype is like superclass but stops at the last instance of a Content class
      def supertype=(supertype)
        @supertype = supertype
      end

      def supertype
        @supertype
      end

      def descendents
        subclasses.map{ |x| [x] + x.descendents}.flatten
      end

      def inherited(subclass)
        super
        Spontaneous::Schema.classes << subclass
        subclasses << subclass
        subclass.supertype = self
      end
    end
  end
end


