class Bill < AccountRecord
  # Represents a Bill of Quantities

  belongs_to :account, inverse_of: :bills
  belongs_to :project, inverse_of: :bills
  has_many :packages, dependent: :destroy, inverse_of: :bill

  validates :name, presence: true
  validate :project_belongs_to_same_account

  before_validation :set_default_name, on: :create

  private

  def project_belongs_to_same_account
    return unless project && account_id
    errors.add(:project, "must belong to the same account") if project.account_id != account_id
  end

  def set_default_name
    self.name ||= "Bill of Quantities - #{Time.current.strftime('%b %-d, %Y')}"
  end
end
