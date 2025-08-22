# Ticket 1: Create Element Model

**Epic**: M2 Specification Input  
**Story Points**: 3  
**Dependencies**: M-01 (Project model)

## Description
Create the Element model that stores building specifications for each project. Elements represent individual building components (walls, doors, windows, etc.) with their raw specifications and extracted parameters. This model bridges user input to AI processing.

## Acceptance Criteria
- [ ] Element model with project association and specification fields
- [ ] Support for raw specification text and extracted parameters
- [ ] JSON field for flexible parameter storage
- [ ] Status tracking for processing pipeline
- [ ] Model validations and account scoping
- [ ] Comprehensive test coverage

## Code to be Written

### 1. Migration
```ruby
# db/migrate/xxx_create_elements.rb
class CreateElements < ActiveRecord::Migration[8.0]
  def change
    create_table :elements do |t|
      t.references :project, null: false, foreign_key: true
      t.string :name, null: false
      t.text :specification, null: false
      t.json :extracted_params, default: {}
      t.json :user_params, default: {}
      t.string :status, null: false, default: 'pending'
      t.string :element_type
      t.decimal :confidence_score, precision: 5, scale: 4
      t.text :ai_notes
      t.datetime :processed_at

      t.timestamps
    end

    add_index :elements, :project_id
    add_index :elements, [:project_id, :status]
    add_index :elements, [:project_id, :created_at]
    add_index :elements, :status
  end
end
```

### 2. Element Model
```ruby
# app/models/element.rb
class Element < ApplicationRecord
  belongs_to :project
  has_many :quantities, dependent: :destroy
  has_many :assemblies, through: :quantities

  STATUSES = %w[pending processing processed verified failed].freeze
  ELEMENT_TYPES = %w[
    wall door window floor ceiling roof foundation beam column slab 
    stairs railing fixture electrical plumbing hvac
  ].freeze

  validates :name, presence: true, length: { maximum: 255 }
  validates :specification, presence: true, length: { minimum: 10 }
  validates :status, inclusion: { in: STATUSES }
  validates :element_type, inclusion: { in: ELEMENT_TYPES }, allow_blank: true
  validates :confidence_score, 
    numericality: { 
      greater_than_or_equal_to: 0, 
      less_than_or_equal_to: 1 
    }, 
    allow_nil: true

  scope :for_account, ->(account) { joins(:project).where(projects: { account: account }) }
  scope :by_status, ->(status) { where(status: status) }
  scope :recent, -> { order(created_at: :desc) }
  scope :needs_processing, -> { where(status: %w[pending failed]) }
  scope :processed, -> { where(status: %w[processed verified]) }

  def combined_params
    extracted_params.merge(user_params)
  end

  def missing_params
    required_params = assemblies.flat_map { |a| a.inputs_schema&.keys || [] }.uniq
    required_params - combined_params.keys
  end

  def processing_complete?
    %w[processed verified].include?(status)
  end

  def needs_verification?
    status == 'processed' && confidence_score.present? && confidence_score < 0.8
  end

  def mark_as_processing!
    update!(status: 'processing', processed_at: Time.current)
  end

  def mark_as_processed!(params = {})
    update!(
      status: 'processed',
      extracted_params: params[:extracted_params] || {},
      confidence_score: params[:confidence_score],
      element_type: params[:element_type],
      ai_notes: params[:ai_notes],
      processed_at: Time.current
    )
  end

  def mark_as_verified!
    update!(status: 'verified')
  end

  def mark_as_failed!(error_message = nil)
    update!(
      status: 'failed',
      ai_notes: error_message,
      processed_at: Time.current
    )
  end

  def to_s
    "#{name} (#{project.title})"
  end

  def specification_preview(limit = 100)
    specification.length > limit ? "#{specification[0..limit]}..." : specification
  end
end
```

### 3. Element Concern for Account Scoping
```ruby
# app/models/concerns/element_scoping.rb
module ElementScoping
  extend ActiveSupport::Concern

  included do
    scope :for_account, ->(account) { joins(:project).where(projects: { account: account }) }
    
    def account
      project&.account
    end
    
    def account_id
      project&.account_id
    end
  end
end
```

### 4. Model Tests
```ruby
# test/models/element_test.rb
require "test_helper"

class ElementTest < ActiveSupport::TestCase
  def setup
    @project = projects(:office_building)
    @element = Element.new(
      project: @project,
      name: "External Wall",
      specification: "100mm blockwork with 50mm insulation and brick outer leaf"
    )
  end

  test "should be valid with valid attributes" do
    assert @element.valid?
  end

  test "should require name" do
    @element.name = nil
    assert_not @element.valid?
    assert_includes @element.errors[:name], "can't be blank"
  end

  test "should require specification" do
    @element.specification = nil
    assert_not @element.valid?
    assert_includes @element.errors[:specification], "can't be blank"
  end

  test "should require minimum specification length" do
    @element.specification = "short"
    assert_not @element.valid?
    assert_includes @element.errors[:specification], "is too short (minimum is 10 characters)"
  end

  test "should have default status of pending" do
    @element.save!
    assert_equal "pending", @element.status
  end

  test "should validate status inclusion" do
    @element.status = "invalid_status"
    assert_not @element.valid?
    assert_includes @element.errors[:status], "is not included in the list"
  end

  test "should validate confidence score range" do
    @element.confidence_score = 1.5
    assert_not @element.valid?
    assert_includes @element.errors[:confidence_score], "must be less than or equal to 1"

    @element.confidence_score = -0.1
    assert_not @element.valid?
    assert_includes @element.errors[:confidence_score], "must be greater than or equal to 0"
  end

  test "should belong to project" do
    @element.project = nil
    assert_not @element.valid?
    assert_includes @element.errors[:project], "must exist"
  end

  test "should scope by account" do
    @element.save!
    other_account = accounts(:personal)
    other_project = Project.create!(
      account: other_account,
      client: "Other Client",
      title: "Other Project",
      address: "456 Other St",
      region: "Manchester"
    )
    other_element = Element.create!(
      project: other_project,
      name: "Other Element",
      specification: "Different specification for testing"
    )

    account_elements = Element.for_account(@project.account)
    assert_includes account_elements, @element
    assert_not_includes account_elements, other_element
  end

  test "should combine extracted and user params" do
    @element.extracted_params = { "width" => 10, "height" => 3 }
    @element.user_params = { "height" => 3.5, "material" => "brick" }
    
    combined = @element.combined_params
    assert_equal 10, combined["width"]
    assert_equal 3.5, combined["height"] # user params override
    assert_equal "brick", combined["material"]
  end

  test "should track processing status changes" do
    @element.save!
    
    @element.mark_as_processing!
    assert_equal "processing", @element.status
    assert_not_nil @element.processed_at

    @element.mark_as_processed!(
      extracted_params: { "width" => 10 },
      confidence_score: 0.95,
      element_type: "wall"
    )
    assert_equal "processed", @element.status
    assert_equal 0.95, @element.confidence_score
    assert_equal "wall", @element.element_type
  end

  test "should identify elements needing verification" do
    @element.save!
    @element.mark_as_processed!(confidence_score: 0.7)
    
    assert @element.needs_verification?
    
    @element.mark_as_processed!(confidence_score: 0.9)
    assert_not @element.needs_verification?
  end

  test "should provide specification preview" do
    long_spec = "A" * 200
    @element.specification = long_spec
    
    preview = @element.specification_preview(50)
    assert_equal 54, preview.length # 50 + "..."
    assert preview.ends_with?("...")
  end

  test "should return account through project" do
    @element.save!
    assert_equal @project.account, @element.account
    assert_equal @project.account_id, @element.account_id
  end
end
```

### 5. Fixtures
```yaml
# test/fixtures/elements.yml
external_wall:
  project: office_building
  name: "External Wall - South Elevation"
  specification: "225mm cavity wall construction comprising 100mm concrete blockwork inner leaf, 75mm rigid foam insulation, 50mm cavity, and 102.5mm facing brick outer leaf with stainless steel wall ties at 450mm centres."
  status: pending

internal_partition:
  project: office_building
  name: "Internal Partition Wall"
  specification: "100mm metal stud partition with 12.5mm plasterboard each side, taped and filled ready for decoration."
  status: processed
  extracted_params: { "width": 100, "height": 2700, "material": "metal_stud" }
  confidence_score: 0.92
  element_type: wall
  processed_at: <%= 1.hour.ago %>

entrance_door:
  project: residential_block
  name: "Main Entrance Door"
  specification: "Solid core timber door 838mm x 1981mm x 44mm with architectural ironmongery including 3-lever mortice lock, hinges, and closer."
  status: verified
  extracted_params: { "width": 838, "height": 1981, "thickness": 44, "material": "timber" }
  user_params: { "fire_rating": "FD30" }
  confidence_score: 0.98
  element_type: door
  processed_at: <%= 2.hours.ago %>
```

## Technical Notes
- Use JSON fields for flexible parameter storage without schema changes
- Status enum drives the processing pipeline workflow
- Confidence scoring helps identify elements needing human verification
- Combined params method merges AI and user inputs with user precedence
- Account scoping follows Jumpstart Pro patterns through project relationship

## Definition of Done
- [ ] Migration runs successfully
- [ ] Model passes all tests
- [ ] Fixtures created and working
- [ ] Status transitions work correctly
- [ ] JSON parameter handling functions properly
- [ ] Account scoping implemented correctly
- [ ] Code review completed