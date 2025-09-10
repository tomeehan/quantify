class Account < ApplicationRecord
  has_prefix_id :acct

  include Billing
  include Domains
  include Transfer
  include Types

  # Tenant-owned resources
  has_many :projects, dependent: :destroy, inverse_of: :account
  has_many :bills, dependent: :destroy, inverse_of: :account
  has_many :packages, dependent: :destroy, inverse_of: :account
end
