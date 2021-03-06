require File.dirname(__FILE__) + '/../test_helper'

class RoomTest < ActiveSupport::TestCase

  def setup
    @a_conference = conferences(:a_conference)
    @a_room = rooms(:a_room)
  end

  def test_session_conflicts
    count = @a_room.sessions.count
    assert count > 0
    assert_equal [], @a_room.session_conflicts
    session = @a_room.sessions.first
    conflict = @a_room.sessions.create!(
      :name		=> "Conflicting Session",
      :portfolio	=> session.portfolio,
      :room		=> @a_room,
      :starts_at	=> session.starts_at,
      :duration		=> 20
    )
    @a_room.reload
    assert_equal count+1, @a_room.sessions.count
    assert 1, @a_room.session_conflicts.count
    assert @a_room.session_conflicts.*.include?(conflict)
  end

  def test_portfolio_lifecycle
    a_portfolio = @a_room.portfolios.first
    a_portfolio.state = "published"
    assert a_portfolio.save
    @a_room.name = "Name Change"
    assert @a_room.save
    assert a_portfolio.reload.changes_pending?
  end

end
