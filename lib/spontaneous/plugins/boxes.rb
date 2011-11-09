# encoding: UTF-8

module Spontaneous::Plugins
  module Boxes

    module ClassMethods
      def box(name, options = {}, &block)
        puts "Adding box #{self}##{self.object_id} // #{name} #{box_prototypes.map { |p| p.name }}"
        puts "Using supertype #{superclass.inspect}##{superclass.object_id}" if superclass
        name = name.to_sym
        prototype = nil
        unless boxes.key?(name)
          options[:group] = @box_group if @box_group
          prototype = Spontaneous::Prototypes::BoxPrototype.new(self, name, options, &block)
          box_prototypes[name] = prototype
          unless method_defined?(name)
            class_eval <<-BOX
              def #{name}
                boxes[:#{name}]
              end
            BOX
          end
        end
        prototype
      end

      def boxes
        box_prototypes
      end

      def box_prototypes
        @box_prototypes ||= Spontaneous::Collections::PrototypeSet.new(superclass, :box_prototypes)
      end

      def has_boxes?
        !box_prototypes.empty?
      end

      def box_order(*new_order)
        box_prototypes.order = new_order.flatten
      end

      def box?(box_name)
        box_prototypes.key?(box_name.to_sym)
      end

      def is_box?
        false
      end

      def box_group(name, &block)
        @box_group = name #box_groups[name.to_sym]
        yield if block_given?
      ensure
        @box_group = nil
      end
    end

    module InstanceMethods

      def reload
        @boxes = nil
        super
      end

      def boxes(*args)
        @boxes ||= Spontaneous::Collections::BoxSet.new(self)
      end

      def iterable
        boxes
      end


      def box?(box_name)
        self.class.box?(box_name.to_sym)
      end

      def box_data(box)
        # TODO: use schema id to retrieve box data
        box_id = box.schema_id.to_s
        (self.box_store || []).detect { |data| data[:box_id] == box_id } || {}
      end

      def box_field_store(box)
        box_data(box)[:fields]
      end

      def box_modified!(modified_box)
        self.box_store = serialize_boxes
      end

      def serialize_boxes
        boxes.map { |box| box.serialize_db }
      end

      def box_style_id(box_name)
        nil
      end
    end
  end
end
