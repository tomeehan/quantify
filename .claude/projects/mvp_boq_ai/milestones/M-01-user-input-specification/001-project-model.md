# Ticket 1: Create Project Model

**Epic**: M1 Project Creation  
**Story Points**: 2  
**Dependencies**: None

## Description
Create the core Project model that will serve as the container for all BoQ work. Projects belong to accounts (following Jumpstart Pro multi-tenancy patterns) and contain basic metadata needed for BoQ generation.

## Acceptance Criteria
- [ ] Project model with required fields: client, title, address, region
- [ ] Belongs to account relationship (Jumpstart Pro pattern)
- [ ] Basic validations for required fields
- [ ] Model includes account scoping module
- [ ] Test coverage for model validations and relationships

## Code to be Written

### 1. Migration
```ruby
# db/migrate/xxx_create_projects.rb
class CreateProjects < ActiveRecord::Migration[8.0]
  def change
    create_table :projects do |t|
      t.references :account, null: false, foreign_key: true
      t.string :client, null: false
      t.string :title, null: false
      t.text :address, null: false
      t.string :region, null: false
      t.text :description

      t.timestamps
    end

    add_index :projects, :account_id
    add_index :projects, [:account_id, :created_at]
  end
end
```

### 2. Project Model
```ruby
# app/models/project.rb
class Project < ApplicationRecord
  belongs_to :account
  has_many :elements, dependent: :destroy

  validates :client, presence: true, length: { maximum: 255 }
  validates :title, presence: true, length: { maximum: 255 }
  validates :address, presence: true
  validates :region, presence: true, length: { maximum: 100 }

  scope :for_account, ->(account) { where(account: account) }
  scope :recent, -> { order(created_at: :desc) }

  def to_s
    "#{title} - #{client}"
  end

  def location_summary
    "#{region}"
  end
end
```

### 3. Model Tests
```ruby
# test/models/project_test.rb
require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  def setup
    @account = accounts(:company)
    @project = Project.new(
      account: @account,
      client: "ACME Construction",
      title: "Office Building Project",
      address: "123 Main St, London",
      region: "London"
    )
  end

  test "should be valid with valid attributes" do
    assert @project.valid?
  end

  test "should require client" do
    @project.client = nil
    assert_not @project.valid?
    assert_includes @project.errors[:client], "can't be blank"
  end

  test "should require title" do
    @project.title = nil
    assert_not @project.valid?
    assert_includes @project.errors[:title], "can't be blank"
  end

  test "should require address" do
    @project.address = nil
    assert_not @project.valid?
    assert_includes @project.errors[:address], "can't be blank"
  end

  test "should require region" do
    @project.region = nil
    assert_not @project.valid?
    assert_includes @project.errors[:region], "can't be blank"
  end

  test "should belong to account" do
    @project.account = nil
    assert_not @project.valid?
    assert_includes @project.errors[:account], "must exist"
  end

  test "should scope by account" do
    @project.save!
    other_account = accounts(:personal)
    other_project = Project.create!(
      account: other_account,
      client: "Other Client",
      title: "Other Project",
      address: "456 Other St",
      region: "Manchester"
    )

    account_projects = Project.for_account(@account)
    assert_includes account_projects, @project
    assert_not_includes account_projects, other_project
  end

  test "to_s should return title and client" do
    expected = "#{@project.title} - #{@project.client}"
    assert_equal expected, @project.to_s
  end
end
```

## Technical Notes
- Follow Jumpstart Pro patterns for account-scoped models
- Use descriptive validation messages
- Index on account_id for query performance
- Model should be simple and focused - complex logic goes in services

## Definition of Done
- [ ] Migration runs successfully
- [ ] Model passes all tests
- [ ] Fixtures are created and working
- [ ] Model follows Jumpstart Pro conventions
- [ ] Code review completed