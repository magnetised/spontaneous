module Spontaneous

  module Model
    autoload :Core,  "spontaneous/model/core"
    autoload :Page,  "spontaneous/model/page"
    autoload :Piece, "spontaneous/model/piece"
    autoload :Box,   "spontaneous/model/box"
  end

  def self.models
    @models ||= {}
  end

  def self.Model(table_name, database = Spontaneous.database, schema = Site.schema)
    define_content_model(table_name, database, schema)
  end

  def self.define_content_model(table_name, database = Spontaneous.database, schema = Site.schema)
    model = Spontaneous::DataMapper::Model(table_name, database, schema) do
      serialize_columns :field_store, :entry_store, :box_store, :serialized_modifications
      include_all_types
    end
    model.class_eval do
      many_to_one :owner,      :key => :owner_id, :model => self, :reciprocal => :_pieces
      one_to_many :_pieces,    :key => :owner_id, :model => self, :reciprocal => :owner
      many_to_one :page,       :key => :page_id,  :model => self, :reciprocal => :content
      many_to_one :created_by, :key => :created_by_id, :model => Spontaneous::Permissions::User
      # '__target' rather than 'target' because we want to override the behaviour of the
      # Content#target method only on classes that are aliases, and this is defined dynamically
      many_to_one :__target,   :key => :target_id, :model => self, :reciprocal => :aliases
      one_to_many :aliases,    :key => :target_id, :model => self, :reciprocal => :__target, :dependent => :destroy
    end
    model.send :extend,  ContentModelClassMethods
    model.send :include, ContentModelInstanceMethods
    model
  end

  module ContentModelClassMethods
    # Can't just use the @@ syntax here because it gets scoped to the
    # enclosing module rather than the generated class...
    def content_model
      class_variable_get(:@@content_model)
    end

    # This is fiddly because we want the Content.content_model to refer to the
    # first subclass of the Spontaneous::Content call as that is going to be our
    # ::Content model. In this particular instance I want the behaviour of Ruby's
    # class variables -- I want a single value to be shared across all subclasses
    # Use this moment to include the core functionality because this is the first
    # access to the subclass derived from the base model.
    def inherited(subclass)
      unless class_variable_defined?(:@@content_model)
        class_variable_set(:@@content_model, subclass)
        subclass.send :include, Spontaneous::Model::Core
      end
      super
    end

    def const_missing(name)
      # Only the top-level content model has the auto generated
      # Page & Piece models
      return super unless content_model == self
      case name
      when :Page, :Piece
        klass = Class.new(self) do
          include_types { subclasses }
          def self.inherited(subclass, real_caller = nil)
            __determine_source_file(subclass, real_caller || caller[0])
            subclass.include_types { [self] }
            super
          end
        end
        klass.send :include, ::Spontaneous::Model.const_get(name)
        const_set(name, klass)
        klass
      when :Box
        klass = Class.new(Spontaneous::Box)
        klass.send :include, ::Spontaneous::Model.const_get(name)
        klass.instance_variable_set(:"@mapper", mapper)
        const_set(name, klass)
        klass
      else
        super
      end
    end

    def pages
      content_model::Page.all
    end
  end

  module ContentModelInstanceMethods
    def content_model
      model.content_model
    end
  end
end
