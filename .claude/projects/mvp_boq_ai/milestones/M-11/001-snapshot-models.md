# Ticket 1: Snapshot Management System

**Epic**: M11 Snapshot Management  
**Story Points**: 4  
**Dependencies**: M-10 (Export capabilities)

## Description
Create comprehensive snapshot system that preserves historical versions of BoQ data for audit compliance, comparison analysis, and change tracking. Supports automated snapshots, manual captures, and detailed comparison views.

## Acceptance Criteria
- [ ] Snapshot model with complete project state capture
- [ ] Automated snapshot triggers on significant changes
- [ ] Manual snapshot creation with user annotations
- [ ] Snapshot comparison functionality
- [ ] Historical data preservation and compliance
- [ ] Snapshot restoration capabilities (view-only)
- [ ] Storage optimization for large projects

## Code to be Written

### 1. Project Snapshot Model
```ruby
# app/models/project_snapshot.rb
class ProjectSnapshot < ApplicationRecord
  belongs_to :project
  belongs_to :created_by, class_name: 'User'
  
  has_many :snapshot_elements, dependent: :destroy
  has_many :snapshot_boq_lines, dependent: :destroy

  TRIGGER_TYPES = %w[manual auto_verification auto_generation rate_update].freeze
  
  validates :name, presence: true
  validates :trigger_type, inclusion: { in: TRIGGER_TYPES }
  validates :snapshot_data, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :manual, -> { where(trigger_type: 'manual') }
  scope :automatic, -> { where.not(trigger_type: 'manual') }

  def self.create_snapshot(project, user, options = {})
    snapshot = new(
      project: project,
      created_by: user,
      name: options[:name] || generate_default_name(project),
      description: options[:description],
      trigger_type: options[:trigger_type] || 'manual'
    )
    
    snapshot.capture_project_state!
    snapshot
  end

  def capture_project_state!
    transaction do
      # Capture project metadata
      self.snapshot_data = {
        project_details: capture_project_details,
        totals: capture_project_totals,
        statistics: capture_statistics,
        captured_at: Time.current
      }
      
      save!
      
      # Capture elements
      capture_elements!
      
      # Capture BoQ lines
      capture_boq_lines!
      
      Rails.logger.info("Snapshot created", {
        project_id: project.id,
        snapshot_id: id,
        elements_count: snapshot_elements.count,
        boq_lines_count: snapshot_boq_lines.count
      })
    end
  end

  def compare_with(other_snapshot)
    SnapshotComparison.new(self, other_snapshot).compare
  end

  def total_value
    snapshot_data.dig('totals', 'grand_total') || 0
  end

  def elements_count
    snapshot_elements.count
  end

  def boq_lines_count
    snapshot_boq_lines.count
  end

  def summary_stats
    {
      total_value: total_value,
      elements_count: elements_count,
      verified_elements: snapshot_elements.where(status: 'verified').count,
      boq_lines_count: boq_lines_count,
      created_at: created_at
    }
  end

  private

  def capture_project_details
    {
      title: project.title,
      client: project.client,
      address: project.address,
      region: project.region,
      description: project.description
    }
  end

  def capture_project_totals
    project_total = ProjectTotal.find_by(project: project)
    return {} unless project_total
    
    {
      total_labour: project_total.total_labour,
      total_plant: project_total.total_plant,
      total_material: project_total.total_material,
      total_overhead: project_total.total_overhead,
      subtotal: project_total.subtotal,
      grand_total: project_total.grand_total,
      calculated_at: project_total.calculated_at
    }
  end

  def capture_statistics
    {
      total_elements: project.elements.count,
      verified_elements: project.elements.by_status('verified').count,
      pending_elements: project.elements.by_status('pending').count,
      failed_elements: project.elements.by_status('failed').count,
      processing_elements: project.elements.by_status('processing').count
    }
  end

  def capture_elements!
    project.elements.find_each do |element|
      snapshot_elements.create!(
        element_id: element.id,
        name: element.name,
        specification: element.specification,
        element_type: element.element_type,
        status: element.status,
        extracted_params: element.extracted_params,
        user_params: element.user_params,
        confidence_score: element.confidence_score,
        ai_notes: element.ai_notes,
        processed_at: element.processed_at
      )
    end
  end

  def capture_boq_lines!
    project.boq_lines.includes(:quantity, :rate, :element).find_each do |line|
      snapshot_boq_lines.create!(
        boq_line_id: line.id,
        element_name: line.element&.name,
        description: line.description,
        unit: line.unit,
        quantity_amount: line.quantity_amount,
        rate_per_unit: line.rate_per_unit,
        total_amount: line.total_amount,
        rate_type: line.rate&.rate_type,
        calculation_data: line.calculation_data
      )
    end
  end

  def self.generate_default_name(project)
    timestamp = Time.current.strftime("%Y-%m-%d %H:%M")
    "#{project.title} - #{timestamp}"
  end
end
```

### 2. Snapshot Element Model
```ruby
# app/models/snapshot_element.rb
class SnapshotElement < ApplicationRecord
  belongs_to :project_snapshot
  
  validates :element_id, presence: true
  validates :name, presence: true
  validates :specification, presence: true
  validates :status, presence: true

  scope :by_status, ->(status) { where(status: status) }
  scope :verified, -> { where(status: 'verified') }

  def confidence_percentage
    return 0 unless confidence_score.present?
    (confidence_score * 100).round(1)
  end

  def has_user_modifications?
    user_params.present? && user_params.any?
  end
end
```

### 3. Snapshot BoQ Line Model
```ruby
# app/models/snapshot_boq_line.rb
class SnapshotBoqLine < ApplicationRecord
  belongs_to :project_snapshot
  
  validates :description, presence: true
  validates :unit, presence: true
  validates :quantity_amount, presence: true, numericality: { greater_than: 0 }
  validates :rate_per_unit, presence: true, numericality: { greater_than: 0 }
  validates :total_amount, presence: true, numericality: { greater_than: 0 }

  scope :by_rate_type, ->(type) { where(rate_type: type) }

  def self.total_by_rate_type
    group(:rate_type).sum(:total_amount)
  end
end
```

### 4. Snapshot Comparison Service
```ruby
# app/services/snapshot_comparison.rb
class SnapshotComparison
  attr_reader :baseline_snapshot, :comparison_snapshot

  def initialize(baseline_snapshot, comparison_snapshot)
    @baseline_snapshot = baseline_snapshot
    @comparison_snapshot = comparison_snapshot
  end

  def compare
    {
      summary: compare_summary,
      totals: compare_totals,
      elements: compare_elements,
      boq_lines: compare_boq_lines,
      metadata: {
        baseline_date: baseline_snapshot.created_at,
        comparison_date: comparison_snapshot.created_at,
        time_difference: time_difference_description
      }
    }
  end

  private

  def compare_summary
    baseline_stats = baseline_snapshot.summary_stats
    comparison_stats = comparison_snapshot.summary_stats
    
    {
      total_value_change: comparison_stats[:total_value] - baseline_stats[:total_value],
      total_value_change_percent: percentage_change(baseline_stats[:total_value], comparison_stats[:total_value]),
      elements_count_change: comparison_stats[:elements_count] - baseline_stats[:elements_count],
      verified_elements_change: comparison_stats[:verified_elements] - baseline_stats[:verified_elements],
      boq_lines_change: comparison_stats[:boq_lines_count] - baseline_stats[:boq_lines_count]
    }
  end

  def compare_totals
    baseline_totals = baseline_snapshot.snapshot_data['totals'] || {}
    comparison_totals = comparison_snapshot.snapshot_data['totals'] || {}
    
    %w[total_labour total_plant total_material total_overhead grand_total].map do |total_type|
      baseline_value = baseline_totals[total_type] || 0
      comparison_value = comparison_totals[total_type] || 0
      
      {
        type: total_type,
        baseline_value: baseline_value,
        comparison_value: comparison_value,
        change: comparison_value - baseline_value,
        change_percent: percentage_change(baseline_value, comparison_value)
      }
    end
  end

  def compare_elements
    baseline_elements = baseline_snapshot.snapshot_elements.index_by(&:element_id)
    comparison_elements = comparison_snapshot.snapshot_elements.index_by(&:element_id)
    
    {
      added: find_added_elements(baseline_elements, comparison_elements),
      removed: find_removed_elements(baseline_elements, comparison_elements),
      modified: find_modified_elements(baseline_elements, comparison_elements)
    }
  end

  def compare_boq_lines
    baseline_lines = baseline_snapshot.snapshot_boq_lines.group_by(&:description)
    comparison_lines = comparison_snapshot.snapshot_boq_lines.group_by(&:description)
    
    {
      added_lines: find_added_boq_lines(baseline_lines, comparison_lines),
      removed_lines: find_removed_boq_lines(baseline_lines, comparison_lines),
      value_changes: find_boq_value_changes(baseline_lines, comparison_lines)
    }
  end

  def find_added_elements(baseline, comparison)
    added_ids = comparison.keys - baseline.keys
    comparison.values_at(*added_ids).compact
  end

  def find_removed_elements(baseline, comparison)
    removed_ids = baseline.keys - comparison.keys
    baseline.values_at(*removed_ids).compact
  end

  def find_modified_elements(baseline, comparison)
    common_ids = baseline.keys & comparison.keys
    
    common_ids.filter_map do |element_id|
      baseline_element = baseline[element_id]
      comparison_element = comparison[element_id]
      
      if elements_different?(baseline_element, comparison_element)
        {
          element_id: element_id,
          name: comparison_element.name,
          changes: detect_element_changes(baseline_element, comparison_element)
        }
      end
    end
  end

  def elements_different?(baseline, comparison)
    %w[status confidence_score extracted_params user_params].any? do |field|
      baseline.send(field) != comparison.send(field)
    end
  end

  def detect_element_changes(baseline, comparison)
    changes = {}
    
    if baseline.status != comparison.status
      changes[:status] = { from: baseline.status, to: comparison.status }
    end
    
    if baseline.confidence_score != comparison.confidence_score
      changes[:confidence] = { 
        from: baseline.confidence_score, 
        to: comparison.confidence_score 
      }
    end
    
    changes
  end

  def find_added_boq_lines(baseline, comparison)
    added_descriptions = comparison.keys - baseline.keys
    comparison.values_at(*added_descriptions).flatten.compact
  end

  def find_removed_boq_lines(baseline, comparison)
    removed_descriptions = baseline.keys - comparison.keys
    baseline.values_at(*removed_descriptions).flatten.compact
  end

  def find_boq_value_changes(baseline, comparison)
    common_descriptions = baseline.keys & comparison.keys
    
    common_descriptions.filter_map do |description|
      baseline_line = baseline[description].first
      comparison_line = comparison[description].first
      
      if baseline_line.total_amount != comparison_line.total_amount
        {
          description: description,
          baseline_total: baseline_line.total_amount,
          comparison_total: comparison_line.total_amount,
          change: comparison_line.total_amount - baseline_line.total_amount,
          change_percent: percentage_change(baseline_line.total_amount, comparison_line.total_amount)
        }
      end
    end
  end

  def percentage_change(old_value, new_value)
    return 0 if old_value.zero?
    ((new_value - old_value) / old_value.to_f * 100).round(2)
  end

  def time_difference_description
    diff = comparison_snapshot.created_at - baseline_snapshot.created_at
    days = (diff / 1.day).round
    
    if days < 1
      hours = (diff / 1.hour).round
      "#{hours} hour#{'s' if hours != 1}"
    else
      "#{days} day#{'s' if days != 1}"
    end
  end
end
```

### 5. Snapshot Controller
```ruby
# app/controllers/projects/snapshots_controller.rb
class Projects::SnapshotsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_project
  before_action :set_snapshot, only: [:show, :destroy, :compare]

  def index
    authorize @project
    @snapshots = @project.project_snapshots.includes(:created_by).recent.limit(50)
  end

  def show
    authorize @snapshot
    @snapshot_stats = @snapshot.summary_stats
    @elements = @snapshot.snapshot_elements.includes(:project_snapshot)
    @boq_lines = @snapshot.snapshot_boq_lines.includes(:project_snapshot)
  end

  def new
    authorize @project
    @snapshot = @project.project_snapshots.build
  end

  def create
    authorize @project
    
    begin
      @snapshot = ProjectSnapshot.create_snapshot(
        @project,
        current_user,
        {
          name: params[:name],
          description: params[:description],
          trigger_type: 'manual'
        }
      )
      
      respond_to do |format|
        format.html { redirect_to project_snapshot_path(@project, @snapshot), notice: "Snapshot created successfully." }
        format.turbo_stream do
          flash.now[:notice] = "Snapshot created successfully."
        end
      end
      
    rescue => e
      Rails.logger.error("Failed to create snapshot", {
        project_id: @project.id,
        error: e.message
      })
      
      respond_to do |format|
        format.html { redirect_to project_snapshots_path(@project), alert: "Failed to create snapshot: #{e.message}" }
        format.turbo_stream do
          flash.now[:alert] = "Failed to create snapshot: #{e.message}"
        end
      end
    end
  end

  def compare
    authorize @snapshot
    
    comparison_snapshot = @project.project_snapshots.find(params[:compare_with])
    authorize comparison_snapshot
    
    @comparison = @snapshot.compare_with(comparison_snapshot)
    @baseline_snapshot = @snapshot
    @comparison_snapshot = comparison_snapshot
  end

  def destroy
    authorize @snapshot
    
    @snapshot.destroy
    
    respond_to do |format|
      format.html { redirect_to project_snapshots_path(@project), notice: "Snapshot deleted." }
      format.turbo_stream do
        flash.now[:notice] = "Snapshot deleted."
      end
    end
  end

  private

  def set_project
    @project = current_account.projects.find(params[:project_id])
  end

  def set_snapshot
    @snapshot = @project.project_snapshots.find(params[:id])
  end
end
```

## Technical Notes
- Complete state capture preserves all project data
- Efficient comparison algorithms handle large datasets
- Automatic triggering ensures compliance documentation
- JSON storage optimizes space while maintaining flexibility
- Background processing for large project snapshots

## Definition of Done
- [ ] Snapshots capture complete project state
- [ ] Automatic snapshot triggers work correctly
- [ ] Comparison functionality provides detailed analysis
- [ ] Manual snapshot creation functions properly
- [ ] Historical preservation maintains data integrity
- [ ] Storage optimization handles large projects
- [ ] Test coverage exceeds 90%
- [ ] Code review completed