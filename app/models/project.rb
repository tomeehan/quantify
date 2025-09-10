class Project < AccountRecord
  # Attributes: name, address, square_footage, project_type (enum)

  # Multitenancy: every project belongs to an account (tenant)
  belongs_to :account, inverse_of: :projects

  has_many :bills, dependent: :destroy, inverse_of: :project

  enum :project_type, %i[commercial residential], default: :commercial

  validates :name, presence: true
  validates :square_footage, numericality: {only_integer: true, greater_than_or_equal_to: 0}, allow_nil: true
end
