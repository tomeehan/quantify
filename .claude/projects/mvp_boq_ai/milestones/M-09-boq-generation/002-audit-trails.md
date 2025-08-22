# Ticket 2: BoQ Audit Trails & Integrity

**Epic**: M9 BoQ Line Generation  
**Story Points**: 4  
**Dependencies**: 001-boq-line-generation.md

## Description
Implement comprehensive audit trails for all BoQ line generation activities, ensuring complete traceability from original specification through to final priced line. Provide integrity checks and validation to ensure BoQ accuracy and compliance.

## Acceptance Criteria
- [ ] Complete audit trail from specification to final BoQ line
- [ ] Tamper-evident audit records with cryptographic integrity
- [ ] Real-time validation of BoQ line calculations
- [ ] Comprehensive change tracking for all BoQ modifications
- [ ] Audit report generation for compliance purposes
- [ ] Data integrity checks and validation alerts

## Code to be Written

### 1. BoQ Audit Trail Model
```ruby
# app/models/boq_audit_trail.rb
class BoqAuditTrail < ApplicationRecord
  belongs_to :project
  belongs_to :boq_line, optional: true
  belongs_to :user, optional: true

  validates :event_type, presence: true
  validates :event_data, presence: true
  validates :checksum, presence: true

  serialize :event_data, JSON
  serialize :metadata, JSON

  enum event_type: {
    line_created: 0,
    line_updated: 1,
    line_deleted: 2,
    rate_applied: 3,
    rate_updated: 4,
    quantity_recalculated: 5,
    manual_override: 6,
    assembly_changed: 7,
    parameter_updated: 8,
    nrm_code_changed: 9,
    boq_finalized: 10,
    snapshot_created: 11,
    export_generated: 12
  }

  scope :recent, -> { order(created_at: :desc) }
  scope :for_project, ->(project) { where(project: project) }
  scope :for_line, ->(boq_line) { where(boq_line: boq_line) }

  before_create :generate_checksum
  after_create :validate_chain_integrity

  def self.create_audit_entry(project:, boq_line: nil, user: nil, event_type:, event_data:, metadata: {})
    create!(
      project: project,
      boq_line: boq_line,
      user: user,
      event_type: event_type,
      event_data: event_data,
      metadata: metadata.merge({
        timestamp: Time.current.iso8601,
        user_agent: metadata[:user_agent],
        ip_address: metadata[:ip_address],
        sequence_number: next_sequence_number(project)
      })
    )
  end

  def verify_integrity
    expected_checksum = calculate_checksum
    checksum == expected_checksum
  end

  def event_summary
    case event_type
    when "line_created"
      "BoQ line created: #{event_data['description']} (#{event_data['quantity']} #{event_data['unit']})"
    when "line_updated"
      changes = event_data['changes'] || {}
      changed_fields = changes.keys.join(', ')
      "BoQ line updated: #{changed_fields}"
    when "rate_applied"
      "Rate applied: #{event_data['rate_value']} per #{event_data['rate_unit']}"
    when "quantity_recalculated"
      "Quantity recalculated: #{event_data['old_quantity']} → #{event_data['new_quantity']}"
    when "manual_override"
      "Manual override: #{event_data['field']} changed to #{event_data['new_value']}"
    else
      event_type.humanize
    end
  end

  def self.generate_integrity_report(project)
    audit_records = for_project(project).order(:created_at)
    
    integrity_issues = []
    
    audit_records.each do |record|
      unless record.verify_integrity
        integrity_issues << {
          record_id: record.id,
          event_type: record.event_type,
          created_at: record.created_at,
          issue: "Checksum mismatch - possible tampering"
        }
      end
    end
    
    # Check for sequence gaps
    sequence_numbers = audit_records.pluck(:metadata).map { |m| m['sequence_number'] }.compact.sort
    expected_sequence = (1..sequence_numbers.last).to_a
    missing_sequences = expected_sequence - sequence_numbers
    
    missing_sequences.each do |seq|
      integrity_issues << {
        sequence_number: seq,
        issue: "Missing audit record in sequence"
      }
    end
    
    {
      project_id: project.id,
      project_title: project.title,
      total_audit_records: audit_records.count,
      integrity_issues: integrity_issues,
      is_valid: integrity_issues.empty?,
      generated_at: Time.current.iso8601
    }
  end

  private

  def generate_checksum
    self.checksum = calculate_checksum
  end

  def calculate_checksum
    # Create a tamper-evident checksum using the previous record's checksum
    previous_record = BoqAuditTrail.where(project: project)
                                   .where("created_at < ?", created_at || Time.current)
                                   .order(:created_at)
                                   .last
    
    previous_checksum = previous_record&.checksum || "genesis"
    
    data_string = [
      project_id,
      boq_line_id,
      user_id,
      event_type,
      event_data.to_json,
      metadata.to_json,
      previous_checksum
    ].compact.join("|")
    
    Digest::SHA256.hexdigest(data_string)
  end

  def validate_chain_integrity
    return if project.boq_audit_trails.count == 1 # First record
    
    # Verify this record's checksum includes the previous record's checksum
    previous_record = project.boq_audit_trails.where("id < ?", id).order(:id).last
    
    if previous_record && !checksum.include?(previous_record.checksum)
      Rails.logger.error "Audit trail integrity violation detected for project #{project.id}"
    end
  end

  def self.next_sequence_number(project)
    last_sequence = project.boq_audit_trails.maximum("(metadata->>'sequence_number')::integer") || 0
    last_sequence + 1
  end
end
```

### 2. BoQ Integrity Validator Service
```ruby
# app/services/boq_integrity_validator.rb
class BoqIntegrityValidator
  include ActiveModel::Model

  attr_reader :project, :validation_errors, :validation_warnings

  def initialize(project)
    @project = project
    @validation_errors = []
    @validation_warnings = []
  end

  def validate_boq_integrity
    validate_line_calculations
    validate_rate_consistency  
    validate_quantity_logic
    validate_total_calculations
    validate_audit_trail_completeness
    validate_nrm_compliance

    {
      is_valid: validation_errors.empty?,
      has_warnings: validation_warnings.any?,
      errors: validation_errors,
      warnings: validation_warnings,
      validated_at: Time.current.iso8601
    }
  end

  def validate_line_calculations
    project.boq_lines.includes(:quantity, :rate).each do |line|
      # Verify quantity × rate = total
      expected_total = (line.quantity.quantity * line.rate.rate_per_unit).round(2)
      actual_total = line.total.round(2)
      
      unless expected_total == actual_total
        add_error("Line calculation mismatch", 
                 "Line #{line.id}: Expected #{expected_total}, got #{actual_total}")
      end
      
      # Verify units match
      unless line.quantity.unit == line.rate.unit
        add_warning("Unit mismatch", 
                   "Line #{line.id}: Quantity unit '#{line.quantity.unit}' != Rate unit '#{line.rate.unit}'")
      end
    end
  end

  def validate_rate_consistency
    # Check for rate changes that might affect calculations
    project.boq_lines.joins(:rate).group(:rate_id).having("COUNT(*) > 1").each do |rate_group|
      rate = Rate.find(rate_group.rate_id)
      
      # Check if rate has been updated since some BoQ lines were created
      latest_line = project.boq_lines.where(rate: rate).order(:updated_at).last
      
      if rate.updated_at > latest_line.updated_at
        add_warning("Rate updated after BoQ line creation",
                   "Rate #{rate.id} updated at #{rate.updated_at}, but line #{latest_line.id} created at #{latest_line.updated_at}")
      end
    end
  end

  def validate_quantity_logic
    project.elements.includes(:quantities).each do |element|
      element.quantities.each do |quantity|
        # Verify quantity is positive
        if quantity.quantity <= 0
          add_warning("Non-positive quantity", 
                     "Element '#{element.name}' has quantity #{quantity.quantity}")
        end
        
        # Verify quantity calculation is recent relative to parameter updates
        if element.updated_at > quantity.updated_at
          add_warning("Outdated quantity calculation",
                     "Element '#{element.name}' parameters updated after quantity calculation")
        end
      end
    end
  end

  def validate_total_calculations
    # Verify project total matches sum of line totals
    calculated_total = project.boq_lines.sum(:total)
    recorded_total = project.total_cost
    
    unless calculated_total.round(2) == recorded_total&.round(2)
      add_error("Project total mismatch",
               "Sum of lines: #{calculated_total}, Recorded total: #{recorded_total}")
    end
  end

  def validate_audit_trail_completeness
    # Verify every BoQ line has creation audit trail
    project.boq_lines.each do |line|
      creation_audit = BoqAuditTrail.for_line(line).where(event_type: :line_created).first
      
      unless creation_audit
        add_error("Missing audit trail", "BoQ line #{line.id} has no creation audit record")
      end
      
      # Verify audit trail integrity
      line_audits = BoqAuditTrail.for_line(line)
      line_audits.each do |audit|
        unless audit.verify_integrity
          add_error("Audit trail corruption", "Audit record #{audit.id} failed integrity check")
        end
      end
    end
  end

  def validate_nrm_compliance
    project.elements.includes(:nrm_item).each do |element|
      next unless element.nrm_item
      
      # Verify element has required assemblies for its NRM code
      required_assemblies = element.nrm_item.assemblies.where(required: true)
      actual_quantities = element.quantities.joins(:assembly)
      
      missing_assemblies = required_assemblies.where.not(
        id: actual_quantities.select(:assembly_id)
      )
      
      if missing_assemblies.any?
        missing_titles = missing_assemblies.pluck(:title).join(', ')
        add_warning("Missing required assemblies",
                   "Element '#{element.name}' missing: #{missing_titles}")
      end
    end
  end

  private

  def add_error(category, message)
    @validation_errors << {
      category: category,
      message: message,
      severity: "error",
      timestamp: Time.current.iso8601
    }
  end

  def add_warning(category, message)
    @validation_warnings << {
      category: category,
      message: message,
      severity: "warning", 
      timestamp: Time.current.iso8601
    }
  end
end
```

### 3. BoQ Line Callbacks for Audit Trail
```ruby
# Update app/models/boq_line.rb to include audit callbacks
class BoqLine < ApplicationRecord
  belongs_to :quantity
  belongs_to :rate
  has_many :boq_audit_trails, dependent: :destroy

  validates :total, presence: true, numericality: { greater_than: 0 }
  
  after_create :create_audit_trail_for_creation
  after_update :create_audit_trail_for_update
  after_destroy :create_audit_trail_for_deletion

  delegate :project, to: :quantity
  delegate :element, to: :quantity

  def calculate_total!
    new_total = (quantity.quantity * rate.rate_per_unit).round(2)
    
    if new_total != total
      old_total = total
      update!(total: new_total)
      
      create_calculation_audit_trail(old_total, new_total)
    end
    
    new_total
  end

  def apply_rate!(new_rate)
    old_rate = rate
    old_total = total
    
    self.rate = new_rate
    calculate_total!
    save!
    
    create_rate_change_audit_trail(old_rate, new_rate)
  end

  def manual_override!(field, new_value, user, reason)
    old_value = send(field)
    
    update!(field => new_value)
    
    BoqAuditTrail.create_audit_entry(
      project: project,
      boq_line: self,
      user: user,
      event_type: :manual_override,
      event_data: {
        field: field,
        old_value: old_value,
        new_value: new_value,
        reason: reason
      }
    )
  end

  private

  def create_audit_trail_for_creation
    BoqAuditTrail.create_audit_entry(
      project: project,
      boq_line: self,
      user: Current.user,
      event_type: :line_created,
      event_data: {
        description: description,
        quantity: quantity.quantity,
        unit: quantity.unit,
        rate: rate.rate_per_unit,
        total: total,
        element_name: element.name,
        assembly_title: quantity.assembly.title
      }
    )
  end

  def create_audit_trail_for_update
    return unless saved_changes.any?
    
    BoqAuditTrail.create_audit_entry(
      project: project,
      boq_line: self,
      user: Current.user,
      event_type: :line_updated,
      event_data: {
        changes: saved_changes,
        description: description
      }
    )
  end

  def create_audit_trail_for_deletion
    BoqAuditTrail.create_audit_entry(
      project: project,
      boq_line: nil, # Line is being deleted
      user: Current.user,
      event_type: :line_deleted,
      event_data: {
        deleted_line_id: id,
        description: description,
        quantity: quantity.quantity,
        total: total
      }
    )
  end

  def create_calculation_audit_trail(old_total, new_total)
    BoqAuditTrail.create_audit_entry(
      project: project,
      boq_line: self,
      user: Current.user,
      event_type: :rate_applied,
      event_data: {
        old_total: old_total,
        new_total: new_total,
        quantity: quantity.quantity,
        rate: rate.rate_per_unit,
        calculation: "#{quantity.quantity} × #{rate.rate_per_unit} = #{new_total}"
      }
    )
  end

  def create_rate_change_audit_trail(old_rate, new_rate)
    BoqAuditTrail.create_audit_entry(
      project: project,
      boq_line: self,
      user: Current.user,
      event_type: :rate_updated,
      event_data: {
        old_rate_id: old_rate.id,
        old_rate_value: old_rate.rate_per_unit,
        new_rate_id: new_rate.id,
        new_rate_value: new_rate.rate_per_unit,
        rate_change_reason: "Rate update applied"
      }
    )
  end
end
```

### 4. Audit Trail Migration
```ruby
# db/migrate/xxx_create_boq_audit_trails.rb
class CreateBoqAuditTrails < ActiveRecord::Migration[8.0]
  def change
    create_table :boq_audit_trails do |t|
      t.references :project, null: false, foreign_key: true
      t.references :boq_line, null: true, foreign_key: true
      t.references :user, null: true, foreign_key: true
      
      t.integer :event_type, null: false
      t.json :event_data, null: false
      t.json :metadata
      t.string :checksum, null: false
      
      t.timestamps
    end

    add_index :boq_audit_trails, :project_id
    add_index :boq_audit_trails, :boq_line_id
    add_index :boq_audit_trails, :event_type
    add_index :boq_audit_trails, [:project_id, :created_at]
    add_index :boq_audit_trails, :checksum
  end
end
```

### 5. Audit Trail Controller
```ruby
# app/controllers/audit_trails_controller.rb
class AuditTrailsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_project

  def index
    authorize @project, :show?
    
    @audit_trails = @project.boq_audit_trails
                           .includes(:boq_line, :user)
                           .order(created_at: :desc)
                           .page(params[:page])
                           .per(50)
    
    @integrity_report = BoqAuditTrail.generate_integrity_report(@project)
  end

  def show
    @audit_trail = @project.boq_audit_trails.find(params[:id])
    authorize @audit_trail
  end

  def integrity_report
    authorize @project, :show?
    
    report = BoqAuditTrail.generate_integrity_report(@project)
    validation_result = BoqIntegrityValidator.new(@project).validate_boq_integrity
    
    respond_to do |format|
      format.json { 
        render json: {
          audit_integrity: report,
          boq_validation: validation_result
        }
      }
      format.pdf {
        # Generate PDF report
        pdf = AuditReportPdf.new(@project, report, validation_result)
        send_data pdf.render, 
                  filename: "audit_report_#{@project.id}_#{Date.current}.pdf",
                  type: "application/pdf"
      }
    end
  end

  private

  def set_project
    @project = current_account.projects.find(params[:project_id])
  end
end
```

### 6. Audit Trail Tests
```ruby
# test/models/boq_audit_trail_test.rb
require "test_helper"

class BoqAuditTrailTest < ActiveSupport::TestCase
  setup do
    @project = projects(:office_building)
    @boq_line = boq_lines(:concrete_foundation_line)
    @user = users(:one)
  end

  test "creates audit entry with checksum" do
    audit = BoqAuditTrail.create_audit_entry(
      project: @project,
      boq_line: @boq_line,
      user: @user,
      event_type: :line_created,
      event_data: { description: "Test line" }
    )
    
    assert audit.persisted?
    assert audit.checksum.present?
    assert audit.verify_integrity
  end

  test "generates tamper-evident checksums" do
    # Create first audit entry
    audit1 = BoqAuditTrail.create_audit_entry(
      project: @project,
      event_type: :line_created,
      event_data: { test: "data1" }
    )
    
    # Create second audit entry
    audit2 = BoqAuditTrail.create_audit_entry(
      project: @project,
      event_type: :line_created,
      event_data: { test: "data2" }
    )
    
    # Second audit should include first audit's checksum
    assert audit2.checksum.include?(audit1.checksum)
  end

  test "detects integrity violations" do
    audit = BoqAuditTrail.create_audit_entry(
      project: @project,
      event_type: :line_created,
      event_data: { test: "data" }
    )
    
    # Tamper with the audit record
    audit.update_column(:event_data, { tampered: "data" })
    
    # Integrity check should fail
    assert_not audit.verify_integrity
  end

  test "generates integrity report" do
    # Create some audit entries
    3.times do |i|
      BoqAuditTrail.create_audit_entry(
        project: @project,
        event_type: :line_created,
        event_data: { test: "data#{i}" }
      )
    end
    
    report = BoqAuditTrail.generate_integrity_report(@project)
    
    assert report[:is_valid]
    assert_equal 3, report[:total_audit_records]
    assert_empty report[:integrity_issues]
  end

  test "tracks sequence numbers" do
    audit1 = BoqAuditTrail.create_audit_entry(
      project: @project,
      event_type: :line_created,
      event_data: { test: "data1" }
    )
    
    audit2 = BoqAuditTrail.create_audit_entry(
      project: @project,
      event_type: :line_created,
      event_data: { test: "data2" }
    )
    
    assert_equal 1, audit1.metadata['sequence_number']
    assert_equal 2, audit2.metadata['sequence_number']
  end
end
```

## Technical Notes
- Cryptographic checksums ensure tamper-evident audit trails
- Chain-of-custody tracking provides complete traceability
- Real-time integrity validation detects calculation errors
- Comprehensive audit coverage includes all BoQ modifications
- Performance optimized for large projects with many audit records

## Definition of Done
- [ ] Audit trail captures all BoQ line changes
- [ ] Checksum validation detects tampering attempts
- [ ] Integrity validator identifies calculation errors
- [ ] Audit reports provide compliance documentation
- [ ] Chain-of-custody tracking works correctly
- [ ] Performance is acceptable for large audit volumes
- [ ] All tests pass with >95% coverage
- [ ] Code review completed