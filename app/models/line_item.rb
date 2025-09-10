class LineItem < AccountRecord
  belongs_to :account, inverse_of: :line_items
  belongs_to :package, inverse_of: :line_items

  UNITS = %w[m2 m m3 inch ft yd cm mm kg each lot].freeze

  validates :item, presence: true
  validates :quantity, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :unit, presence: true, inclusion: { in: UNITS }
  validates :rate, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :markup, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :total, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :package_belongs_to_same_account

  before_validation :sync_account_from_package
  before_validation :compute_total

  private

  def sync_account_from_package
    self.account_id ||= package&.account_id
  end

  def package_belongs_to_same_account
    return unless package && account_id
    errors.add(:package, "must belong to the same account") if package.account_id != account_id
  end

  def compute_total
    q = (quantity || 0).to_d
    r = (rate || 0).to_d
    self.total = (q * r)
  end
end

