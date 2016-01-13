class Player < ActiveRecord::Base

  has_attached_file :avatar, styles: {
      tiny: '24x24>',
      thumb: '100x100>',
      square: '200x200#',
      medium: '300x300>'
  }

  # Validate the attached image is image/jpg, image/png, etc
  validates_attachment_content_type :avatar, :content_type => /\Aimage\/.*\Z/


  has_many :ratings, dependent: :destroy do
    def find_or_create(game)
      where(game_id: game.id).first || create({game: game, pro: false}.merge(game.rater.default_attributes))
    end
  end

  has_and_belongs_to_many :teams

  has_many :results, through: :teams do
    def against(opponent)
      joins("INNER JOIN teams AS other_teams ON results.id = other_teams.result_id")
        .where("other_teams.id != teams.id")
        .joins("INNER JOIN players_teams AS other_players_teams ON other_teams.id = other_players_teams.team_id")
        .where("other_players_teams.player_id = ?", opponent)
    end

    def losses
      where("teams.rank > ?", Team::FIRST_PLACE_RANK)
    end

  end

  before_destroy do
    results.each { |result| result.destroy }
  end

  validates :name, uniqueness: true, presence: true
  validates :email, allow_blank: true, format: /@/

  def as_json
    {
      name: name,
      email: email
    }
  end

  def is_active?
    results.where("results.created_at > :last_active_date", {last_active_date: DateTime.now - 30.days}).count > 0
  end

  def recent_results
    results.order("created_at DESC").limit(5)
  end

  def rewind_rating!(game)
    rating = ratings.where(game_id: game.id).first
    rating.rewind!
  end

  def total_ties(game)
    results.where(game_id: game).to_a.count { |r| r.tie? }
  end

  def ties(game, opponent)
    results.where(game_id: game).against(opponent).to_a.count { |r| r.tie? }
  end

  def total_wins(game)
    results.where(game_id: game, teams: { rank: Team::FIRST_PLACE_RANK }).to_a.count { |r| !r.tie? }
  end

  def wins(game, opponent)
    results.where(game_id: game, teams: {rank: Team::FIRST_PLACE_RANK}).against(opponent).to_a.count { |r| !r.tie? }
  end

  def win_loss_ratio(game)
    total_games = results.for_game(game).size
    0 if total_games == 0
    total_wins(game)/total_games.to_f * 100
  end

  def last_n(game, n)
    results_array = results.where(game_id: game).order("created_at DESC").to_a
    win_loss_array = results_array.collect {|result| result.winners.include?(self) ? 'W' : 'L'}
    win_loss_array.take(n).join("")
  end

  def streak(game)
    results_array = results.where(game_id: game).order("created_at DESC").to_a.chunk do |result|
      result.winners.include?(self)
    end.collect{|e, a| {:is_winner => e, :size => a.size}}
    return 0 if results_array.empty?
    results_array.first[:is_winner] ? results_array.first[:size] : 0
  end

end