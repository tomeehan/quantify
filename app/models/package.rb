class Package < AccountRecord
  belongs_to :account, inverse_of: :packages
  belongs_to :bill, inverse_of: :packages
  has_many :line_items, dependent: :destroy, inverse_of: :package

  validates :name, presence: true
  validate :bill_belongs_to_same_account

  before_validation :sync_account_from_bill

  private

  def sync_account_from_bill
    self.account_id ||= bill&.account_id
  end

  def bill_belongs_to_same_account
    return unless bill && account_id
    errors.add(:bill, "must belong to the same account") if bill.account_id != account_id
  end
end
