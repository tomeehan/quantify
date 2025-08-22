# Ticket 1: BoQ Line Generation Engine

**Epic**: M9 BoQ Line Generation  
**Story Points**: 4  
**Dependencies**: M-08 (Rate application)

## Description
Create comprehensive BoQ line generation system that combines quantities and rates into final Bill of Quantities lines with detailed calculations, totals, and audit trails. Supports project-level aggregation and real-time updates.

## Acceptance Criteria
- [ ] BoQ line model with complete calculation data
- [ ] Project-level BoQ aggregation and totals
- [ ] Real-time line updates when quantities or rates change
- [ ] Detailed audit trails for all calculations
- [ ] Support for markup, contingency, and project overheads
- [ ] BoQ line grouping and categorization

## Code to be Written

### 1. BoQ Line Model
```ruby
# app/models/boq_line.rb
class BoqLine < ApplicationRecord
  belongs_to :quantity
  belongs_to :rate
  belongs_to :project
  has_one :element, through: :quantity

  validates :description, presence: true
  validates :unit, presence: true
  validates :quantity_amount, presence: true, numericality: { greater_than: 0 }
  validates :rate_per_unit, presence: true, numericality: { greater_than: 0 }
  validates :total_amount, presence: true, numericality: { greater_than: 0 }

  scope :for_project, ->(project) { where(project: project) }
  scope :by_rate_type, ->(type) { joins(:rate).where(rates: { rate_type: type }) }
  scope :ordered, -> { joins(:quantity, :element).order('elements.name, rates.rate_type') }

  before_save :calculate_total
  after_save :update_project_totals
  after_destroy :update_project_totals

  def self.generate_for_quantity(quantity)
    service = RateApplicationService.new(quantity)
    service.apply_rates
  end

  def recalculate!
    self.total_amount = quantity_amount * rate_per_unit
    save!
  end

  def line_number
    project.boq_lines.ordered.index(self) + 1
  end

  def category
    rate.rate_type.humanize
  end

  private

  def calculate_total
    self.total_amount = quantity_amount * rate_per_unit
  end

  def update_project_totals
    ProjectTotalsUpdateJob.perform_later(project)
  end
end
```

### 2. BoQ Generation Service
```ruby
# app/services/boq_generation_service.rb
class BoqGenerationService
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :project
  attribute :options, :hash, default: {}

  def generate
    Rails.logger.info("Starting BoQ generation", { project_id: project.id })
    
    results = {
      lines_created: 0,
      lines_updated: 0,
      total_value: 0,
      generation_time: nil
    }
    
    start_time = Time.current
    
    # Process all verified elements
    verified_elements = project.elements.by_status('verified').includes(:quantities, :assemblies, :rates)
    
    verified_elements.each do |element|
      process_element_quantities(element, results)
    end
    
    # Apply project-level adjustments
    apply_project_adjustments(results)
    
    results[:generation_time] = ((Time.current - start_time) * 1000).round
    results[:total_value] = calculate_project_total
    
    Rails.logger.info("BoQ generation completed", results.merge(project_id: project.id))
    
    results
  end

  private

  def process_element_quantities(element, results)
    element.quantities.includes(:assembly, :rate).each do |quantity|
      next unless quantity.calculated_amount.present?
      
      # Generate or update BoQ lines for this quantity
      boq_lines = BoqLine.generate_for_quantity(quantity)
      
      boq_lines.each do |line|
        if line.persisted? && line.saved_changes.keys.any?
          results[:lines_updated] += 1
        elsif line.persisted?
          results[:lines_created] += 1
        end
      end
    end
  end

  def apply_project_adjustments(results)
    return unless options[:apply_adjustments]
    
    # Apply markup if specified
    if options[:markup_percentage].present?
      apply_markup(options[:markup_percentage])
    end
    
    # Apply contingency if specified
    if options[:contingency_percentage].present?
      apply_contingency(options[:contingency_percentage])
    end
    
    # Apply project overheads
    if options[:overhead_percentage].present?
      apply_overheads(options[:overhead_percentage])
    end
  end

  def apply_markup(percentage)
    markup_amount = calculate_project_total * (percentage / 100.0)
    
    BoqLine.create!(
      project: project,
      description: "Markup (#{percentage}%)",
      unit: "sum",
      quantity_amount: 1,
      rate_per_unit: markup_amount,
      total_amount: markup_amount,
      calculation_data: {
        type: "markup",
        percentage: percentage,
        base_amount: calculate_project_total,
        calculated_at: Time.current
      }
    )
  end

  def apply_contingency(percentage)
    base_total = calculate_project_total
    contingency_amount = base_total * (percentage / 100.0)
    
    BoqLine.create!(
      project: project,
      description: "Contingency (#{percentage}%)",
      unit: "sum",
      quantity_amount: 1,
      rate_per_unit: contingency_amount,
      total_amount: contingency_amount,
      calculation_data: {
        type: "contingency",
        percentage: percentage,
        base_amount: base_total,
        calculated_at: Time.current
      }
    )
  end

  def calculate_project_total
    project.boq_lines.where.not(calculation_data: { type: %w[markup contingency overhead] }).sum(:total_amount)
  end
end
```

### 3. Project Totals Model
```ruby
# app/models/project_total.rb
class ProjectTotal < ApplicationRecord
  belongs_to :project

  validates :total_labour, :total_plant, :total_material, :total_overhead,
            :subtotal, :grand_total, presence: true,
            numericality: { greater_than_or_equal_to: 0 }

  def self.calculate_for_project(project)
    totals = project.boq_lines.joins(:rate).group('rates.rate_type').sum(:total_amount)
    
    find_or_initialize_by(project: project).tap do |project_total|
      project_total.assign_attributes(
        total_labour: totals['labour'] || 0,
        total_plant: totals['plant'] || 0,
        total_material: totals['material'] || 0,
        total_overhead: totals['overhead'] || 0,
        subtotal: totals.values.sum,
        calculated_at: Time.current
      )
      
      # Calculate grand total with any project-level adjustments
      adjustments = calculate_adjustments(project)
      project_total.grand_total = project_total.subtotal + adjustments
      
      project_total.save!
    end
  end

  def breakdown
    {
      labour: total_labour,
      plant: total_plant,
      material: total_material,
      overhead: total_overhead,
      subtotal: subtotal,
      adjustments: grand_total - subtotal,
      grand_total: grand_total
    }
  end

  private

  def self.calculate_adjustments(project)
    adjustment_types = %w[markup contingency]
    project.boq_lines
           .where(calculation_data: { type: adjustment_types })
           .sum(:total_amount)
  end
end
```

### 4. BoQ Generation Job
```ruby
# app/jobs/boq_generation_job.rb
class BoqGenerationJob < ApplicationJob
  include JobErrorHandling
  
  queue_as :calculations
  
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(project, options = {})
    @project = project
    @options = options.with_indifferent_access
    
    Rails.logger.info("Starting BoQ generation job", {
      project_id: project.id,
      options: @options
    })
    
    # Generate BoQ lines
    results = BoqGenerationService.new(project: project, options: @options).generate
    
    # Update project totals
    ProjectTotal.calculate_for_project(project)
    
    # Broadcast completion
    broadcast_completion(results)
    
    results
  end

  private

  def broadcast_completion(results)
    Turbo::StreamsChannel.broadcast_action_to(
      "project_#{@project.id}",
      action: :replace,
      target: "boq_summary",
      partial: "projects/boq_summary",
      locals: { 
        project: @project,
        results: results
      }
    )
    
    Turbo::StreamsChannel.broadcast_action_to(
      "project_#{@project.id}",
      action: :prepend,
      target: "notifications",
      partial: "shared/notification",
      locals: {
        type: :success,
        message: "BoQ generated successfully - #{results[:lines_created]} lines created"
      }
    )
  end
end
```

### 5. BoQ Controller
```ruby
# app/controllers/projects/boqs_controller.rb
class Projects::BoqsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_project

  def show
    authorize @project
    
    @boq_lines = @project.boq_lines.includes(:quantity, :rate, :element).ordered
    @project_total = ProjectTotal.find_by(project: @project)
    @generation_stats = calculate_generation_stats
  end

  def generate
    authorize @project, :update?
    
    options = {
      apply_adjustments: params[:apply_adjustments] == "true",
      markup_percentage: params[:markup_percentage]&.to_f,
      contingency_percentage: params[:contingency_percentage]&.to_f,
      overhead_percentage: params[:overhead_percentage]&.to_f
    }
    
    BoqGenerationJob.perform_later(@project, options)
    
    respond_to do |format|
      format.html { redirect_to project_boq_path(@project), notice: "BoQ generation started." }
      format.turbo_stream do
        flash.now[:notice] = "Generating BoQ in background..."
      end
    end
  end

  def regenerate
    authorize @project, :update?
    
    # Clear existing BoQ lines
    @project.boq_lines.destroy_all
    
    # Regenerate
    redirect_to action: :generate
  end

  private

  def set_project
    @project = current_account.projects.find(params[:project_id])
  end

  def calculate_generation_stats
    {
      total_elements: @project.elements.count,
      verified_elements: @project.elements.by_status('verified').count,
      total_lines: @boq_lines.count,
      last_generated: @project_total&.calculated_at
    }
  end
end
```

### 6. Migration for BoQ Lines
```ruby
# db/migrate/xxx_create_boq_lines.rb
class CreateBoqLines < ActiveRecord::Migration[8.0]
  def change
    create_table :boq_lines do |t|
      t.references :quantity, null: true, foreign_key: true
      t.references :rate, null: true, foreign_key: true
      t.references :project, null: false, foreign_key: true
      t.text :description, null: false
      t.string :unit, null: false
      t.decimal :quantity_amount, precision: 12, scale: 4, null: false
      t.decimal :rate_per_unit, precision: 12, scale: 4, null: false
      t.decimal :total_amount, precision: 14, scale: 2, null: false
      t.json :calculation_data, default: {}
      t.integer :line_number
      t.string :category
      t.text :notes

      t.timestamps
    end

    add_index :boq_lines, :project_id
    add_index :boq_lines, [:project_id, :line_number]
    add_index :boq_lines, [:project_id, :category]
    add_index :boq_lines, :total_amount
  end
end

class CreateProjectTotals < ActiveRecord::Migration[8.0]
  def change
    create_table :project_totals do |t|
      t.references :project, null: false, foreign_key: true, index: { unique: true }
      t.decimal :total_labour, precision: 14, scale: 2, default: 0
      t.decimal :total_plant, precision: 14, scale: 2, default: 0
      t.decimal :total_material, precision: 14, scale: 2, default: 0
      t.decimal :total_overhead, precision: 14, scale: 2, default: 0
      t.decimal :subtotal, precision: 14, scale: 2, default: 0
      t.decimal :grand_total, precision: 14, scale: 2, default: 0
      t.datetime :calculated_at
      t.json :breakdown_data, default: {}

      t.timestamps
    end
  end
end
```

## Technical Notes
- Separates line generation from totals calculation for flexibility
- Real-time updates maintain data consistency
- Audit trails support project compliance requirements
- Background processing handles large projects efficiently
- Supports project-level adjustments and markups

## Definition of Done
- [ ] BoQ lines generate correctly from quantities and rates
- [ ] Project totals calculate accurately
- [ ] Real-time updates work via Turbo Streams
- [ ] Background generation handles large projects
- [ ] Audit trails capture all calculations
- [ ] Project adjustments apply correctly
- [ ] Test coverage exceeds 90%
- [ ] Code review completed