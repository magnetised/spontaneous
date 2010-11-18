# encoding: UTF-8

require 'test_helper'


class RenderTest < Test::Unit::TestCase
  include Spontaneous

  def template_root
    @style_root ||= File.expand_path(File.join(File.dirname(__FILE__), "../fixtures/templates"))
  end

  context "Content objects" do
    setup do
      Spontaneous::Render.template_root = template_root
      Spontaneous::Render.engine_class = Cutaneous::FirstRenderEngine

      class ::TemplateClass < Content
        field :title do
          def to_epub
            to_html
          end
        end
        field :description do
          def to_pdf
            "{#{value}}"
          end
          def to_epub
            to_html
          end
        end

        inline_style :this_template
        inline_style :another_template
      end
      @content = TemplateClass.new
      @content.style.should == TemplateClass.styles.default
      @content.title = "The Title"
      @content.description = "The Description"
    end

    teardown do
      Object.send(:remove_const, :TemplateClass)
    end

    should "be able to render themselves to HTML" do
      @content.render.should == "<html><title>The Title</title><body>The Description</body></html>\n"
    end

    should "be able to render themselves to PDF" do
      @content.render(:pdf).should == "<PDF><title>The Title</title><body>{The Description}</body></PDF>\n"
    end

    should "be able to render themselves to EPUB" do
      @content.render(:epub).should == "<EPUB><title>The Title</title><body>The Description</body></EPUB>\n"
    end

    context "facet trees" do
      setup do
        TemplateClass.inline_style :complex_template, :default => true
        @content = TemplateClass.new
        @content.title = "The Title"
        @content.description = "The Description"
        @child = TemplateClass.new
        @child.title = "Child Title"
        @child.description = "Child Description"
        @content << @child
        @content.entries.first.style = TemplateClass.styles[:this_template]
      end

      should "be accessible through #content method" do
        @content.render.should == "<complex>\nThe Title\n<facet><html><title>Child Title</title><body>Child Description</body></html>\n</facet>\n</complex>\n"
      end

      should "cascade the chosen format to all subsequent #render calls" do
        @content.render(:pdf).should == "<pdf>\nThe Title\n<facet><PDF><title>Child Title</title><body>{Child Description}</body></PDF>\n</facet>\n</pdf>\n"
      end
    end

    context "slots" do
      setup do
        TemplateClass.inline_style :slots_template, :default => true
        TemplateClass.slot :images
        @content = TemplateClass.new
        @content.title = "The Title"
        @content.description = "The Description"
        @child = TemplateClass.new
        @child.title = "Child Title"
        @child.description = "Child Description"
        @content.images << @child
        @content.images.first.style = TemplateClass.styles[:this_template]
      end

      should "render slots" do
        @content.render.should == "<slots>\n  <img><html><title>Child Title</title><body>Child Description</body></html>\n</img>\n</slots>\n"
      end
      should "render slots to alternate formats" do
        @content.render(:pdf).should == "<slots-pdf>\n  <img><PDF><title>Child Title</title><body>{Child Description}</body></PDF>\n</img>\n</slots-pdf>\n"
      end
    end

    context "anonymous slots" do
      setup do
        TemplateClass.inline_style :anonymous_style, :default => true
        TemplateClass.slot :images do
          field :introduction
        end

        class ::AnImage < Content; end
        AnImage.field :title
        AnImage.template '<img>{{title}}</img>'

        @root = TemplateClass.new
        @root.images.introduction = "Images below:"
        @image1 = AnImage.new
        @image1.title = "Image 1"
        @image2 = AnImage.new
        @image2.title = "Image 2"
        @root.images << @image1
        @root.images << @image2
      end

      teardown do
        Object.send(:remove_const, :AnImage)
      end

      should "render using anonymous style" do
        @root.render.should == "<root>\nImages below:\n<img>Image 1</img>\n<img>Image 2</img>\n</root>\n"
      end
    end

    context "default templates" do
      setup do
        TemplateClass.inline_style :default_template_style, :default => true
        TemplateClass.slot :images_with_template do
          field :introduction
        end

        class ::AnImage < Content; end
        AnImage.field :title
        AnImage.template '<img>{{title}}</img>'

        @root = TemplateClass.new
        @root.images_with_template.introduction = "Images below:"
        @image1 = AnImage.new
        @image1.title = "Image 1"
        @image2 = AnImage.new
        @image2.title = "Image 2"
        @root.images_with_template << @image1
        @root.images_with_template << @image2
      end

      teardown do
        Object.send(:remove_const, :AnImage)
      end

      should "render using default style if present" do
        @root.render.should == "<root>\nImages below:\n<images>\n  <img>Image 1</img>\n  <img>Image 2</img>\n</images>\n\n</root>\n"
      end
    end

    context "pages as inline content" do

      setup do
        class ::PageClass < Page; end
        class ::FacetClass < Facet; end
        PageClass.page_style :page_style
        PageClass.inline_style :inline_style
        @parent = PageClass.new
        @parent.title = "Parent"
        @facet = Facet.new
        @page = PageClass.new
        @page.title = "Child"
        @parent << @facet
        @facet << @page
        @parent.save
        @facet.save
        @page.save
      end

      teardown do
        Object.send(:remove_const, :PageClass)
        Object.send(:remove_const, :FacetClass)
      end

      should "use style assigned by entry" do
        @parent.entries.first.entries.first.style.should == PageClass.inline_styles.default
      end

      should "use their default page style when accessed directly" do
        @page = PageClass[@page.id]
        @page.style.should == PageClass.page_styles.default
        @parent.template.should == 'page_class/page_style'
        @page.render.should == "<html></html>\n"
      end

      should "persist sub-page style settings" do
        @parent = Page[@parent.id]
        @parent.entries.first.entries.first.style.should == PageClass.inline_styles.default
      end

      should "render using the inline style" do
        @parent.entries.first.first.template.should == 'page_class/inline_style'
        @parent.entries.first.first.render.should == "Child\n"
        @parent.render.should == "<html>Child\n</html>\n"
      end
    end

    context "params in templates" do
      setup do
        class ::TemplateParams < Page; end
        TemplateParams.field :image, :default_value => "/images/fromage.jpg"
        TemplateParams.page_style :page_style
        @page = TemplateParams.new
      end
      teardown do
        Object.send(:remove_const, :TemplateParams)
      end
      should "be passed to the render call" do
        @page.image.value.should == "/images/fromage.jpg"
        @page.image.src.should == "/images/fromage.jpg"
        @page.render.should =~ /alt="Smelly"/
      end
    end
  end
end

