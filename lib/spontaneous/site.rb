# encoding: UTF-8


module Spontaneous

  class Site < Spontaneous::Facet
    require "spontaneous/site/features"
    require "spontaneous/site/helpers"
    require "spontaneous/site/hooks"
    require "spontaneous/site/instance"
    require "spontaneous/site/level"
    require "spontaneous/site/map"
    require "spontaneous/site/paths"
    require "spontaneous/site/publishing"
    require "spontaneous/site/schema"
    require "spontaneous/site/search"
    require "spontaneous/site/selectors"
    require "spontaneous/site/state"
    require "spontaneous/site/storage"
    require "spontaneous/site/url"

    include Features
    include Helpers
    include Hooks
    include Instance
    include Level
    include Map
    include Paths
    include Publishing
    include Schema
    include Search
    include Selectors
    include State
    include Storage
    include URL

    attr_accessor :database
    attr_reader :environment, :mode, :model

    def initialize(root, env, mode)
      super(root)
      @environment, @mode = env, mode
    end

    def model=(content_model)
      @model = content_model
    end

    def initialize!
      load_config!
      connect_to_database!
      find_plugins!
      load_facets!
      init_facets!
      init_indexes!
    end


    def init_facets!
      facets.each do |facet|
        facet.init!
      end
    end

    def init_indexes!
      facets.each do |facet|
        facet.load_indexes!
      end
    end

    def load_facets!
      load_order.each do |category|
        facets.each { |facet| facet.load_files(category) }
      end
    end


    def reload!
      schema.reload!
      facets.each { |facet| facet.reload_all! }
      schema.validate!
    end


    def connect_to_database!
      self.database = Sequel.connect(db_settings)
      self.database.logger = logger if config.log_queries
    end

    def db_settings
      config_dir = paths.expanded(:config).first
      @db_settings = YAML.load_file(File.join(config_dir, "database.yml"))
      self.config.db = @db_settings[environment]
    end

    def config
      @config ||= Spontaneous::Config.new(environment, mode)
    end

    def find_plugins!
      paths.expanded(:plugins).each do |glob|
        Dir[glob].each do |path|
          load_plugin(path)
        end
      end
    end

    def plugins
      @plugins ||= []
    end

    def facets
      [self] + plugins
    end

    def load_plugin(plugin_root)
      plugin = Spontaneous::Application::Plugin.new(plugin_root)
      self.plugins <<  plugin
      plugin
    end

    # used by publishing mechanism to place files into the appropriate subdirectories
    # in the public folder.
    # Site#file_namespace returns nil so that it's files are placed at the root
    def file_namespace
      nil
    end

    def revision_root
      @revision_dir ||= begin
                          path = Pathname.new(@root / 'cache/revisions')
                          path.mkpath unless path.exist?
                          path.realpath.to_s
                        end
    end

    def revision_dir(revision=nil, root = revision_root)
      root ||= revision_root
      return root / 'current' if revision.nil?
      root / Spontaneous::Paths.pad_revision_number(revision)
    end

    def media_dir(*path)
      media_root = root / "cache/media"
      return media_root if path.empty?
      File.join(media_root, *path)
    end

    def cache_dir(*path)
      cache_root = root / "cache"
      return cache_root if path.empty?
      File.join(cache_root, *path)
    end
  end
end
