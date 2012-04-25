# encoding: UTF-8

require File.expand_path('../../test_helper', __FILE__)


class RevisionsTest < MiniTest::Spec

  def setup
    @now = Time.now
    @site = setup_site
  end

  def teardown
    teardown_site
  end

  context "Content revisions" do
    setup do
      stub_time(@now)

      # DB.logger = Logger.new($stdout)
      Content.delete

      class Page < Spontaneous::Page
        field :title, :string, :default => "New Page"
        box :things
      end
      class Piece < Spontaneous::Piece
        box :things
      end

      @root = Page.create(:uid => "root")
      count = 0
      2.times do |i|
        c = Page.new(:uid => i)
        @root.things << c
        count += 1
        2.times do |j|
          d = Piece.new(:uid => "#{i}.#{j}")
          c.things << d
          count += 1
          2.times do |k|
            d.things << Page.new(:uid => "#{i}.#{j}.#{k}")
            d.save
            count += 1
          end
        end
        c.save
      end
      @root.save
    end

    teardown do
      RevisionsTest.send(:remove_const, :Page) rescue nil
      RevisionsTest.send(:remove_const, :Piece) rescue nil
      Content.delete
      DB.logger = nil
    end

    context "data sources" do

      should "have the right names" do
        Content.revision_table(23).should == '__r00023_content'
        Content.revision_table(nil).should == 'content'
      end

      should "be recognisable" do
        Content.revision_table?('content').should be_false
        Content.revision_table?('__r00023_content').should be_true
        Content.revision_table?('__r00023_not').should be_false
        Content.revision_table?('subscribers').should be_false
      end

      should "be switchable within blocks" do
        Content.dataset.should be_content_revision
        Content.with_revision(23) do
          Content.revision.should ==23
          Content.dataset.should be_content_revision(23)
        end
        Content.dataset.should  be_content_revision
        Content.revision.should be_nil
      end

      should "know which revision is active" do
        Content.with_revision(23) do
          Content.revision.should == 23
        end
      end

      should "understand the with_editable" do
        Content.with_revision(23) do
          Content.dataset.should be_content_revision(23)
          Content.with_editable do
            Content.dataset.should be_content_revision
          end
          Content.dataset.should be_content_revision(23)
        end
        Content.dataset.should be_content_revision
      end

      should "understand with_published" do
        Site.stubs(:published_revision).returns(99)
        Content.with_published do
          Content.dataset.should be_content_revision(99)
          Content.with_editable do
            Content.dataset.should be_content_revision
          end
          Content.dataset.should be_content_revision(99)
        end
        Content.dataset.should be_content_revision
      end

      should "be stackable" do
        Content.dataset.should be_content_revision
        Content.with_revision(23) do
          Content.dataset.should be_content_revision(23)
          Content.with_revision(24) do
            Content.dataset.should be_content_revision(24)
          end
          Content.dataset.should be_content_revision(23)
        end
        Content.dataset.should be_content_revision
      end

      should "reset datasource after an exception" do
        Content.dataset.should be_content_revision
        begin
          Content.with_revision(23) do
            Content.dataset.should be_content_revision(23)
            raise Exception.new
          end
        rescue Exception
        end
        Content.dataset.should be_content_revision
      end

      should "read revision from the environment if present" do
        ENV["SPOT_REVISION"] = '1001'
        Content.with_published do
          Content.dataset.should be_content_revision(1001)
        end
        ENV.delete("SPOT_REVISION")
      end

      context "subclasses" do
        setup do
          class ::Subclass < Page; end
        end

        teardown do
          Object.send(:remove_const, :Subclass)
        end

        should "set all subclasses to use the same dataset" do
          Content.with_revision(23) do
            Subclass.revision.should ==23
            Subclass.dataset.should be_content_revision(23, Subclass.schema_id)
            # piece wasn't loaded until this point
            Piece.dataset.should  be_content_revision(23)
            Piece.revision.should == 23
          end
          Subclass.dataset.should  be_content_revision(nil, Subclass.schema_id)
          Piece.dataset.should  be_content_revision(nil)
        end
      end
    end

    context "content revisions" do
      setup do
        @revision = 1
      end
      teardown do
        Content.delete_revision(@revision)
        Content.delete_revision(@revision+1) rescue nil
      end
      should "be testable for existance" do
        Content.revision_exists?(@revision).should be_false
        Content.create_revision(@revision)
        Content.revision_exists?(@revision).should be_true
      end
      should "be deletable en masse" do
        tables = (1..10).map { |i| Content.revision_table(i).to_sym }
        tables.each do |t|
          DB.create_table(t){Integer :id}
        end
        tables.each do |t|
          DB.tables.include?(t).should be_true
        end
        Content.delete_all_revisions!
        tables.each do |t|
          DB.tables.include?(t).should be_false
        end
      end

      should "be creatable from current content" do
        DB.tables.include?(Content.revision_table(@revision).to_sym).should be_false
        Content.create_revision(@revision)
        DB.tables.include?(Content.revision_table(@revision).to_sym).should be_true
        count = Content.count
        Content.with_revision(@revision) do
          Content.count.should == count
          Content.all.each do |published|
            Content.with_editable do
              e = Content[published.id]
              e.should == published
            end
          end
        end
      end

      should "be creatable from any revision" do
        revision = 2
        source_revision = @revision
        source_revision_count = nil

        Content.create_revision(source_revision)

        Content.with_revision(source_revision) do
          Content.first(:uid => "0").destroy
          source_revision_count = Content.count
        end

        Content.count.should == source_revision_count + 7

        Content.create_revision(revision, source_revision)

        Content.with_revision(revision) do
          Content.count.should == source_revision_count
          Content.all.each do |published|

            Content.with_revision(source_revision) do
              e = Content.first :id => published.id
              e.should == published
            end
          end
        end
      end

      should "have the correct indexes" do
        Content.create_revision(@revision)
        content_indexes = DB.indexes(:content)
        published_indexes = DB.indexes(Content.revision_table(@revision))
        # made slightly complex by the fact that the index names depend on the table names
        # (which are different)
        assert_same_elements published_indexes.values, content_indexes.values
      end


      context "incremental publishing" do
        setup do
          @initial_revision = 1
          @final_revision = 2
          Content.create_revision(@initial_revision)
          Content.delete_revision(@final_revision) rescue nil
          Content.delete_revision(@final_revision+1) rescue nil
        end

        teardown do
          begin
            Content.delete_revision(@initial_revision)
            Content.delete_revision(@final_revision)
            Content.delete_revision(@final_revision+1)
          rescue
          end
          DB.logger = nil
        end

        should "duplicate changes to only a single item" do
          editable1 = Content.first(:uid => '1.0')
          editable1.label.should be_nil
          editable1.label = "published"
          editable1.save
          editable2 = Content.first(:uid => '1.1')
          editable2.label = "unpublished"
          editable2.save
          editable2.reload
          Content.publish(@final_revision, [editable1.id])
          editable1.reload
          Content.with_revision(@final_revision) do
            published = Content.first :id => editable1.id
            unpublished = Content.first :id => editable2.id
            assert_content_equal(published, editable1)

            unpublished.should_not == editable2
          end
        end

        should "publish additions to contents of a page" do
          editable1 = Content.first(:uid => '0')
          new_content = Piece.new(:uid => "new")

          editable1.things << new_content
          editable1.save
          Content.publish(@final_revision, [editable1.id])
          new_content.reload
          editable1.reload
          Content.with_revision(@final_revision) do
            published1 = Content[editable1.id]
            published2 = Content[new_content.id]
            assert_content_equal(published2, new_content)
            assert_content_equal(published1, editable1)
          end
        end

        should "publish deletions to contents of page" do
          editable1 = Content.first(:uid => '0')
          deleted = editable1.contents.first
          editable1.contents.first.destroy
          Content.publish(@final_revision, [editable1.id])
          editable1.reload
          Content.with_revision(@final_revision) do
            published1 = Content[editable1.id]
            assert_content_equal(published1, editable1)
            Content[deleted.id].should be_nil
          end
        end

        should "not publish page additions" do
          editable1 = Content.first(:uid => '0')
          new_page = Page.new(:uid => "new")
          editable1.things << new_page
          editable1.save
          new_page.save
          Content.publish(@final_revision, [editable1.id])
          new_page.reload
          editable1.reload
          Content.with_revision(@final_revision) do
            published1 = Content[editable1.id]
            published2 = Content[new_page.id]
            published2.should be_nil
            assert_content_equal(published1, editable1)
          end
        end

        should "not publish changes to existing pages unless explicitly asked" do
          editable1 = Content.first(:uid => '0')
          editable1.things << Piece.new(:uid => "added")
          editable1.save
          editable2 = Content.first(:uid => '0.0.0')
          new_content = Piece.new(:uid => "new")
          editable2.things << new_content
          editable2.save
          Content.publish(@final_revision, [editable1.id])
          editable1.reload
          editable2.reload
          new_content.reload
          Content.with_revision(@final_revision) do
            published1 = Content.first :id => editable1.id
            Content.first(:uid => "added").should_not be_nil
            published3 = Content.first :id => editable2.id
            assert_content_equal(published1, editable1)
            published3.should_not == editable2
            published3.uid.should_not == "new"
          end
          Content.publish(@final_revision+1, [editable2.id])
          editable1.reload
          editable2.reload
          new_content.reload
          Content.with_revision(@final_revision+1) do
            published1 = Content.first :id => editable1.id
            assert_content_equal(published1, editable1)
            published2 = Content.first :id => editable2.id
            assert_content_equal(published2, editable2)
            published3 = Content.first :id => editable2.contents.first.id
            # published3.should == editable2.contents.first
            assert_content_equal(published3, editable2.contents.first)
          end
        end

        should "insert an entry value into the parent of a newly added page when that page is published" do
          editable1 = Content.first(:uid => '0')
          new_page = Page.new(:uid => "new")
          editable1.things << new_page
          editable1.save
          new_page.save
          Content.publish(@final_revision, [new_page.id])
          new_page.reload
          editable1.reload
          Content.with_revision(@final_revision) do
            published1 = Content[editable1.id]
            published2 = Content[new_page.id]
            assert_content_equal(published2, new_page)
            editable1.entry_store.should == published1.entry_store
          end
        end

        should "choose a sensible position for entry into the parent of a newly added page" do
          editable1 = Content.first(:uid => '0')
          new_page1 = Page.new(:uid => "new1")
          new_page2 = Page.new(:uid => "new2")
          editable1.things << new_page1
          editable1.things << new_page2
          editable1.save
          new_page1.save
          new_page2.save
          Content.publish(@final_revision, [new_page2.id])
          new_page1.reload
          new_page2.reload
          editable1.reload
          Content.with_revision(@final_revision) do
            published1 = Content[editable1.id]
            published2 = Content[new_page1.id]
            published3 = Content[new_page2.id]
            published2.should be_nil
            assert_content_equal(published3, new_page2)
            editable1.entry_store.reject { |e| e[0] == new_page1.id }.should == published1.entry_store
          end
        end

        should "not duplicate entries when publishing pages for the first time" do
          editable1 = Content.first(:uid => '0')
          new_page1 = Page.new(:uid => "new1")
          new_page2 = Page.new(:uid => "new2")
          editable1.things << new_page1
          editable1.things << new_page2
          editable1.save
          new_page1.save
          new_page2.save
          Content.publish(@final_revision, [editable1.id, new_page2.id])
          new_page1.reload
          new_page2.reload
          editable1.reload
          Content.with_revision(@final_revision) do
            published1 = Content[editable1.id]
            published2 = Content[new_page1.id]
            published3 = Content[new_page2.id]
            published2.should be_nil
            assert_content_equal(published3, new_page2)
            assert_content_equal(published1, editable1)
          end
        end

        should "remove deleted pages from the published content" do
          page = Page.first :uid => "0"
          piece = page.things.first
          child = piece.things.first
          page.things.first.destroy
          Content.publish(@final_revision, [page.id])

          Content.with_revision(@final_revision) do
            published_parent = Content[page.id]
            published_piece = Content[piece.id]
            published_page = Content[child.id]
            published_parent.should  == page.reload
            published_piece.should be_nil
            published_page.should be_nil
          end
        end
      end
    end

    context "modification state" do
      should "register creation date of all content" do
        c = Content.create
        c.created_at.to_i.should == @now.to_i
        page = Page.create
        page.created_at.to_i.should == @now.to_i
      end

      should "update modification date of page when page fields are updated" do
        now = @now + 100
        stub_time(now)
        c = Content.first
        (c.modified_at.to_i - @now.to_i).abs.should <= 1
        c.label = "changed"
        c.save
        (c.modified_at - now).abs.should <= 1
      end

      should "update page timestamps on modification of its box fields" do
        Page.box :with_fields do
          field :title
        end

        stub_time(@now+3600)
        page = Page.first :uid => "0"
        (page.modified_at.to_i - @now.to_i).abs.should <= 1
        page.with_fields.title.value = "updated"
        page.save.reload
        page.modified_at.to_i.should == @now.to_i + 3600
      end

      should "update page timestamps on modification of a piece" do
        stub_time(@now+3600)
        page = Page.first :uid => "0"
        (page.modified_at.to_i - @now.to_i).abs.should <= 1
        content = page.contents.first
        content.page.should == page
        content.label = "changed"
        content.save
        page.reload
        page.modified_at.to_i.should == @now.to_i + 3600
      end

      should "update page timestamps on modification of a piece's box fields" do
        Piece.box :with_fields do
          field :title
        end
        stub_time(@now+3600)
        page = Page.first :uid => "0"
        (page.modified_at.to_i - @now.to_i).abs.should <= 1
        content = page.contents.first

        content.with_fields.title.value = "updated"
        content.save
        page.reload
        page.modified_at.to_i.should == @now.to_i + 3600
      end

      should "update page timestamp on addition of piece" do
        stub_time(@now+3600)
        page = Page.first :uid => "0"
        content = Content[page.contents.first.id]
        content.things << Piece.new
        content.save
        content.modified_at.to_i.should == @now.to_i + 3600
        page.reload
        page.modified_at.to_i.should == @now.to_i + 3600
      end

      should "not update the parent page's timestamp on addition of a child page" do
        stub_time(@now+1000)
        page = Page.first :uid => "0"
        page.things << Page.new
        page.save.reload
        page.modified_at.to_i.should == @now.to_i
      end

      should "update a page's timestamp on modification of its slug" do
        stub_time(@now+1000)
        page = Page.first :uid => "0"
        page.slug = "changed"
        page.save.reload
        page.modified_at.to_i.should == @now.to_i + 1000
      end

      should "not update child pages timestamps after changing their parent's slug" do
        page = Page.first :uid => "0.0.0"
        modified = page.modified_at.to_i
        stub_time(@now+1000)
        page = Page.first :uid => "0"
        page.slug = "changed"
        page.save.reload
        page.modified_at.to_i.should == @now.to_i + 1000
        page = Page.first :uid => "0.0.0"
        page.modified_at.to_i.should == modified
      end

      should "update the pages timestamp if a boxes order is changed" do
        stub_time(@now+3600)
        page = Page.first :uid => "0"
        content = Content[page.contents.first.id]
        content.update_position(1)
        page.reload.modified_at.to_i.should == @now.to_i + 3600
      end

      should "update the parent page's modification time if the contents of a piece's box are re-ordered" do
        stub_time(@now+3600)
        page = Page.first :uid => "0"
        content = page.things.first.things.first
        content.update_position(1)
        page.reload.modified_at.to_i.should == @now.to_i + 3600
      end

      should "update the parent page's modification date if a piece is deleted" do
        stub_time(@now+3600)
        page = Page.first :uid => "0"
        content = Content[page.contents.first.id]
        content.destroy
        page.reload.modified_at.to_i.should == @now.to_i + 3600
      end

      should "update the parent page's modification date if a page is deleted" do
        stub_time(@now+3600)
        page = Page.first :uid => "0"
        content = Content[page.things.first.things.first.id]
        content.destroy
        page.reload.modified_at.to_i.should == @now.to_i + 3600
      end

      should "add entry to the list of side effects for a visibility change" do
        stub_time(@now+3600)
        page = Page.first :uid => "1"
        old_slug = page.slug
        page.slug = "changed"
        page.save
        page.reload
        page.pending_modifications.length.should == 1
        mods = page.pending_modifications(:slug)
        mods.length.should == 1
        mod = mods.first
        mod.must_be_instance_of Spontaneous::Plugins::Modifications::SlugModification
        mod.old_value.should == old_slug
        mod.new_value.should == "changed"
        mod.created_at.to_i.should == @now.to_i + 3600
      end

      should "serialize page modifications" do
        stub_time(@now+3600)
        page = Page.first :uid => "1"
        page.slug = "changed"
        page.save
        page.pending_modifications.length.should == 1
        mod = page.pending_modifications(:slug).first
        page = Page.first :id => page.id
        page.pending_modifications.length.should == 1
        page.pending_modifications(:slug).first.should == mod
        page.pending_modifications(:slug).first.created_at.to_i.should == @now.to_i + 3600
      end

      should "concatenate multiple slug modifications together" do
        stub_time(@now+3600)
        page = Page.first :uid => "1"
        old_slug = page.slug
        page.slug = "changed"
        page.save
        page.pending_modifications.length.should == 1
        page.slug = "changed-again"
        page.save
        mod = page.pending_modifications(:slug).first
        mod.old_value.should == old_slug
        mod.new_value.should == "changed-again"
      end

      should "know the number of pages affected by slug modification" do
        stub_time(@now+3600)
        page = Page.first :uid => "1"
        page.slug = "changed"
        page.save
        mod = page.pending_modifications(:slug).first
        mod.count.should == 4
      end

      should "show the number of pages whose visibility is affected in the case of a visibility change" do
        stub_time(@now+3600)
        page = Page.first :uid => "1"
        page.hide!
        page.reload
        mods = page.pending_modifications(:visibility)
        mods.length.should == 1
        mod = mods.first
        mod.count.should == 4
        mod.owner.should == page
      end

      should "record visibility changes that originate from a content piece" do
        stub_time(@now+3600)
        page = Page.first :uid => "1"
        page.things.first.hide!
        page.reload
        mods = page.pending_modifications(:visibility)
        mods.length.should == 1
        mod = mods.first
        mod.count.should == 2
        mod.owner.should == page.things.first
      end

      should "show number of pages that are to be deleted in the case of a deletion" do
        stub_time(@now+3600)
        page = Page.first(:uid => "1")
        owner = page.owner
        page.destroy
        page = Page.first(:uid => "root")
        mods = page.pending_modifications(:deletion)
        mod = mods.first
        # count is number of children of deleted page + 1 (for deleted page)
        mod.count.should == 5
        mod.owner.should == owner.reload
      end

      should "show number of pages deleted if piece with pages is deleted" do
        stub_time(@now+3600)
        page = Page.first(:uid => "1")
        piece = page.things.first
        owner = piece.owner
        piece.destroy
        page = Page.first(:uid => "1")
        mods = page.pending_modifications(:deletion)
        mod = mods.first
        mod.count.should == 2
        mod.owner.should == owner.reload
      end

      should "show number of pages deleted if page belonging to piece is deleted" do
        stub_time(@now+3600)
        page = Page.first(:uid => "1")
        child = page.things.first.things.first
        owner = child.owner
        child.destroy
        page = Page.first(:uid => "1")
        mods = page.pending_modifications(:deletion)
        mod = mods.first
        mod.count.should == 1
        mod.owner.should == owner.reload
      end

      should "have an empty modification if the slug has been reverted to original value" do
        stub_time(@now+3600)
        page = Page.first :uid => "1"
        old_slug = page.slug
        page.slug = "changed"
        page.save
        page.pending_modifications.length.should == 1
        page.slug = "changed-again"
        page.save
        page.slug = old_slug
        page.save
        mods = page.reload.pending_modifications(:slug)
        mods.length.should == 0
      end

      should "have an empty modification if the visibility has been reverted to original value" do
        stub_time(@now+3600)
        page = Page.first :uid => "1"
        page.things.first.hide!
        page.reload
        page.things.first.show!
        page.reload
        mods = page.pending_modifications(:visibility)
        mods.length.should == 0
      end

      context "during publish" do
        setup do
          @initial_revision = 1
          @final_revision = 2
          S::Content.publish(@initial_revision)
        end

        teardown do
          Content.delete_revision(@initial_revision) rescue nil
          Content.delete_revision(@final_revision) rescue nil
        end

        should "act on path change modifications" do
          page = Page.first :uid => "1"
          old_slug = page.slug
          page.slug = "changed"
          page.save
          S::Content.publish(@final_revision, [page.id])
          S::Content.with_revision(@final_revision) do
            %w(1 1.1.1).each do |uid|
              published_page = Page.first :uid => uid
              S::Content.with_editable do
                editable_page = Page.first :uid => uid
                published_page.path.should == editable_page.path
              end
            end
          end
        end

        should "not publish slug changes on pages other than the one being published" do
          #/bands/beatles -> /bands/beatles-changed
          #/bands -> /bands-changed
          # publish(bands)
          # with_published { beatles.path.should == /bands-changed/beatles }
          page = Page.first :uid => "1"
          page.slug = "changed"
          page.save

          child_page = Page.first :uid => "1.0.0"
          old_slug = child_page.slug
          child_page.slug = "changed-too"
          child_page.save

          S::Content.publish(@final_revision, [page.id])
          S::Content.with_revision(@final_revision) do
            published = Page.first :uid => "1.0.0"
            published.path.should == "/changed/#{old_slug}"
          end
        end

        should "act on visibility modifications" do
          page = Page.first :uid => "1"
          page.hide!
          S::Content.publish(@final_revision, [page.id])
          S::Content.with_revision(@final_revision) do
            %w(1 1.1.1).each do |uid|
              published_page = Page.first :uid => uid
              S::Content.with_editable do
                editable_page = Page.first :uid => uid
                published_page.hidden?.should == editable_page.hidden?
              end
            end
          end
        end

        should "act on multiple modifications" do
          page = Page.first :uid => "1"
          page.slug = "changed"
          page.slug = "changed-again"
          page.hide!

          S::Content.publish(@final_revision, [page.id])
          S::Content.with_revision(@final_revision) do
            %w(1 1.1.1).each do |uid|
              published_page = Page.first :uid => uid
              S::Content.with_editable do
                editable_page = Page.first :uid => uid
                published_page.hidden?.should == editable_page.hidden?
                published_page.slug.should == editable_page.slug
                published_page.path.should == editable_page.path
              end
            end
          end
        end

        should "ignore deletion modifications" do
          page = Page.first(:uid => "1")
          page.destroy
          page = Page.first(:uid => "root")
          S::Content.publish(@final_revision, [page.id])
          S::Content.with_revision(@final_revision) do
            %w(1 1.1.1).each do |uid|
              published_page = Page.first :uid => uid
              published_page.should be_nil
            end
            published_page = Page.first :uid => "0"
            published_page.should_not be_nil
          end
        end

        should "clear modifications after publish" do
          page = Page.first :uid => "1"
          page.slug = "changed"
          page.hide!
          S::Content.publish(@final_revision, [page.id])
          page = Page.first :id => page.id
          page.pending_modifications.length.should == 0
        end
      end

    end

    context "publication timestamps" do
      setup do
        @revision = 1
        Content.delete_revision(@revision+1)
      end
      teardown do
        Content.delete_revision(@revision)
        Content.delete_revision(@revision+1)
      end

      should "set correct timestamps on first publish" do
        first = Content.first
        first.reload.first_published_at.should be_nil
        first.reload.last_published_at.should be_nil
        Content.publish(@revision)
        first.reload.first_published_at.to_i.should == @now.to_i
        first.reload.last_published_at.to_i.should == @now.to_i
        first.reload.first_published_revision.should == @revision
        Content.with_editable do
          first.reload.first_published_at.to_i.should == @now.to_i
          first.reload.last_published_at.to_i.should == @now.to_i
          first.reload.first_published_revision.should == @revision
        end
        Content.with_revision(@revision) do
          first.reload.first_published_at.to_i.should == @now.to_i
          first.reload.last_published_at.to_i.should == @now.to_i
          first.reload.first_published_revision.should == @revision
        end
      end

      should "set correct timestamps on later publishes" do
        first = Content.first
        first.first_published_at.should be_nil
        Content.publish(@revision)
        first.reload.first_published_at.to_i.should == @now.to_i
        c = Content.create
        c.first_published_at.should be_nil
        stub_time(@now + 100)
        Content.publish(@revision+1)
        first.reload.first_published_at.to_i.should == @now.to_i
        first.reload.last_published_at.to_i.should == @now.to_i + 100
        Content.with_editable do
          c = Content.first :id => c.id
          c.first_published_at.to_i.should == @now.to_i + 100
        end
        Content.with_revision(@revision+1) do
          c = Content.first :id => c.id
          c.first_published_at.to_i.should == @now.to_i + 100
        end
      end

      should "not set publishing date for items not published" do
        Content.publish(@revision)
        page = Content.first
        page.uid = "fish"
        page.save
        added = Content.create
        added.first_published_at.should be_nil
        Content.publish(@revision+1, [page])
        page.first_published_at.to_i.should == @now.to_i
        added.first_published_at.should be_nil
        added.last_published_at.should be_nil
      end

      should "not set publishing dates if exception raised in passed block" do
        Content.first.first_published_at.should be_nil
        begin
          Content.publish(@revision) do
            raise Exception
          end
        rescue Exception; end
        Content.first.first_published_at.should be_nil
      end

      should "delete revision tables if exception raised in passed block" do
        Content.revision_exists?(@revision).should be_false
        begin
          Content.publish(@revision) do
            Content.revision_exists?(@revision).should be_true
            Content.revision.should == @revision
            raise Exception
          end
        rescue Exception; end
        Content.revision_exists?(@revision).should be_false
      end

      should "always publish all if no previous revisions exist" do
        page = Content.first
        Content.filter(:first_published_at => nil).count.should == Content.count
        Content.publish(@revision, [page])
        Content.filter(:first_published_at => nil).count.should == 0
      end
    end
  end
end