class CfpDueDate

  attr_reader :due_on, :cfps
  attr_accessor :joomla_category, :joomla_menu
  
  def initialize attribs
    @due_on = attribs[:due_on]
    @cfps = attribs[:cfps]
  end

  def name
    "Due #{due_on.strftime('%B %d, %Y')}"
  end

  def populate_joomla_cfp section, menu
    # Kluge: category checked_out_time is not used during the generatation of content,
    #        so co-opt it for sorting purposes (see JoomlaSection::restore_integrity!)
    find_or_create_joomla_category_in section
    find_or_create_joomla_menu_in menu
    cfps.each{|c| c.populate_joomla_call_for_papers joomla_category}
  end

  def find_or_create_joomla_category_in section
    self.joomla_category = section.categories.find_by_title(name) ||
      section.categories.create!(:title => name, :checked_out_time => due_on.to_datetime)
    joomla_category.update_attributes(:alias => nil)
    joomla_category
  end

  def find_or_create_joomla_menu_in menu
    joomla_menu = menu.items.find_by_name(name) || menu.items.create(:name => name)
    joomla_menu.update_attributes(
      :checked_out_time	=> due_on.to_datetime,
      :parent		=> menu.id,
      :sublevel		=> 1,
      :link		=> JoomlaMenu::link_for(joomla_category),
      :alias		=> nil
    )
    joomla_menu
  end

end