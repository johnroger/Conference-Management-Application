class JoomlaSection < ActiveRecord::Base

  set_table_name 'jos_sections'

  def before_validation_on_create
    self.checked_out_time = 5.hours.ago unless checked_out_time
    self.scope = "content"
    self.published = 1
    self.alias = title.tr("A-Z","a-z").gsub(/\W+/,"-") unless self.alias[/\w/]
  end

  has_many :categories, :class_name => "JoomlaCategory", :foreign_key => :section
  has_many :articles, :class_name => "JoomlaArticle", :foreign_key => :sectionid

  acts_as_list :column => :ordering

  validates_presence_of :title
  validates_uniqueness_of :title
  validates_format_of :alias, :with => /^[-\w]+/
  validates_uniqueness_of :alias

  def restore_integrity! order_on = :title
    purge_categories_for_deleted_cfp_due_dates
    categories.all(:order => (order_on||:title)).each_with_index do |category, index|
      category.ordering = index + 1
      category.save
    end
    self.count = articles.count
    save!
  end

  def purge_categories_for_deleted_cfp_due_dates
    return unless self.alias == 'cfp'
    categories.each {|c| c.destroy unless c.articles.count > 0}
  end

end
