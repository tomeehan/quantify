# Ticket 1: Verification Interface

**Epic**: M4 LLM Element Data Verification  
**Story Points**: 4  
**Dependencies**: M-03 (AI processing and extraction)

## Description
Create an intuitive verification interface that allows users to review and confirm AI-extracted element data. The interface should clearly present extracted parameters, highlight low-confidence extractions, provide inline editing capabilities, and track verification status and user modifications.

## Acceptance Criteria
- [ ] Verification dashboard showing elements requiring review
- [ ] Detailed verification interface for individual elements
- [ ] Visual confidence indicators and uncertainty highlighting
- [ ] Inline parameter editing with validation
- [ ] Side-by-side comparison of original specification and extracted data
- [ ] Batch verification capabilities for similar elements
- [ ] Audit trail of user modifications
- [ ] Mobile-responsive design for field verification

## Code to be Written

### 1. Verification Controller
```ruby
# app/controllers/projects/verifications_controller.rb
class Projects::VerificationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_project
  before_action :set_element, only: [:show, :update, :approve, :reject]

  def index
    @pending_elements = @project.elements.by_status('processed').includes(:project)
    @verified_elements = @project.elements.by_status('verified').includes(:project).limit(10)
    @failed_elements = @project.elements.by_status('failed').includes(:project).limit(5)
    
    authorize @pending_elements
    
    @verification_stats = calculate_verification_stats
  end

  def show
    authorize @element
    
    @verification = ElementVerification.find_or_initialize_by(element: @element)
    @parameter_groups = group_parameters_for_display
    @similar_elements = find_similar_elements
    @extraction_confidence = calculate_extraction_confidence
  end

  def update
    authorize @element
    
    @verification = ElementVerification.find_or_initialize_by(element: @element)
    
    if update_element_parameters
      track_verification_changes
      
      respond_to do |format|
        format.html { redirect_to project_verification_path(@project, @element), notice: "Parameters updated successfully." }
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("parameter_form", partial: "parameter_form", locals: { element: @element }),
            turbo_stream.replace("confidence_panel", partial: "confidence_panel", locals: { element: @element }),
            turbo_stream.prepend("flash", partial: "shared/flash", locals: { notice: "Parameters updated" })
          ]
        end
      end
    else
      respond_to do |format|
        format.html { render :show, status: :unprocessable_entity }
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace("parameter_form", partial: "parameter_form", locals: { element: @element })
        end
      end
    end
  end

  def approve
    authorize @element
    
    @verification = ElementVerification.find_or_initialize_by(element: @element)
    
    if @verification.approve!(current_user)
      @element.mark_as_verified!
      
      # Trigger quantity calculation if auto-enabled
      QuantityCalculationJob.perform_later(@element) if auto_calculate_quantities?
      
      respond_to do |format|
        format.html { redirect_to project_verifications_path(@project), notice: "Element approved and verified." }
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.remove("element_#{@element.id}"),
            turbo_stream.prepend("flash", partial: "shared/flash", locals: { notice: "Element verified" }),
            turbo_stream.replace("verification_stats", partial: "verification_stats")
          ]
        end
      end
    else
      respond_to do |format|
        format.html { redirect_to project_verification_path(@project, @element), alert: "Failed to approve element." }
        format.turbo_stream do
          flash.now[:alert] = "Failed to approve element."
        end
      end
    end
  end

  def reject
    authorize @element
    
    @verification = ElementVerification.find_or_initialize_by(element: @element)
    rejection_reason = params[:rejection_reason] || "Manual rejection"
    
    if @verification.reject!(current_user, rejection_reason)
      @element.update!(status: 'pending') # Reset for reprocessing
      
      respond_to do |format|
        format.html { redirect_to project_verifications_path(@project), notice: "Element rejected and queued for reprocessing." }
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.remove("element_#{@element.id}"),
            turbo_stream.prepend("flash", partial: "shared/flash", locals: { notice: "Element rejected" }),
            turbo_stream.replace("verification_stats", partial: "verification_stats")
          ]
        end
      end
    else
      respond_to do |format|
        format.html { redirect_to project_verification_path(@project, @element), alert: "Failed to reject element." }
        format.turbo_stream do
          flash.now[:alert] = "Failed to reject element."
        end
      end
    end
  end

  def batch_approve
    authorize @project, :update?
    
    element_ids = params[:element_ids] || []
    elements = @project.elements.where(id: element_ids, status: 'processed')
    
    approved_count = 0
    elements.each do |element|
      verification = ElementVerification.find_or_initialize_by(element: element)
      if verification.approve!(current_user)
        element.mark_as_verified!
        approved_count += 1
        QuantityCalculationJob.perform_later(element) if auto_calculate_quantities?
      end
    end
    
    respond_to do |format|
      format.html { redirect_to project_verifications_path(@project), notice: "#{approved_count} elements approved." }
      format.turbo_stream do
        flash.now[:notice] = "#{approved_count} elements approved."
      end
    end
  end

  private

  def set_project
    @project = current_account.projects.find(params[:project_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to projects_path, alert: "Project not found."
  end

  def set_element
    @element = @project.elements.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to project_verifications_path(@project), alert: "Element not found."
  end

  def update_element_parameters
    return false unless params[:element].present?
    
    user_params = params[:element][:user_params] || {}
    combined_params = @element.user_params.merge(user_params.permit!)
    
    @element.update(user_params: combined_params)
  end

  def track_verification_changes
    changes = @element.previous_changes[:user_params]
    return unless changes.present?
    
    @verification.track_changes(
      user: current_user,
      field_changes: changes,
      timestamp: Time.current
    )
  end

  def calculate_verification_stats
    total_processed = @project.elements.by_status('processed').count
    total_verified = @project.elements.by_status('verified').count
    avg_confidence = @project.elements.processed.average(:confidence_score) || 0
    
    {
      total_processed: total_processed,
      total_verified: total_verified,
      completion_rate: total_processed > 0 ? (total_verified.to_f / total_processed * 100).round(1) : 0,
      average_confidence: (avg_confidence * 100).round(1)
    }
  end

  def group_parameters_for_display
    return {} unless @element.extracted_params.present?
    
    {
      dimensions: @element.extracted_params["dimensions"] || {},
      materials: @element.extracted_params["materials"] || {},
      finishes: @element.extracted_params["finishes"] || {},
      construction: @element.extracted_params["construction"] || {},
      performance: @element.extracted_params["performance"] || {},
      location: @element.extracted_params["location"] || {}
    }
  end

  def find_similar_elements
    @project.elements
           .where.not(id: @element.id)
           .where(element_type: @element.element_type)
           .by_status('verified')
           .limit(5)
  end

  def calculate_extraction_confidence
    return 0 unless @element.extracted_params.present?
    
    total_fields = @element.extracted_params.values.sum { |group| group.is_a?(Hash) ? group.keys.count : 1 }
    empty_fields = @element.extracted_params.values.sum do |group|
      group.is_a?(Hash) ? group.values.count(&:blank?) : (group.blank? ? 1 : 0)
    end
    
    return 0 if total_fields.zero?
    
    field_completeness = ((total_fields - empty_fields).to_f / total_fields * 100).round(1)
    ai_confidence = (@element.confidence_score || 0) * 100
    
    (field_completeness + ai_confidence) / 2
  end

  def auto_calculate_quantities?
    params[:auto_calculate_quantities] == "true" || @project.settings&.dig("auto_calculate_quantities")
  end
end
```

### 2. Element Verification Model
```ruby
# app/models/element_verification.rb
class ElementVerification < ApplicationRecord
  belongs_to :element
  belongs_to :verified_by, class_name: 'User', optional: true
  belongs_to :rejected_by, class_name: 'User', optional: true

  STATUSES = %w[pending approved rejected].freeze
  
  validates :status, inclusion: { in: STATUSES }
  validates :element, uniqueness: true

  scope :approved, -> { where(status: 'approved') }
  scope :rejected, -> { where(status: 'rejected') }
  scope :pending, -> { where(status: 'pending') }

  def approve!(user)
    update!(
      status: 'approved',
      verified_by: user,
      verified_at: Time.current,
      notes: "Approved by #{user.name}"
    )
  end

  def reject!(user, reason = nil)
    update!(
      status: 'rejected',
      rejected_by: user,
      rejected_at: Time.current,
      rejection_reason: reason,
      notes: "Rejected by #{user.name}: #{reason}"
    )
  end

  def track_changes(user:, field_changes:, timestamp:)
    change_log = changes_log || []
    
    change_log << {
      user_id: user.id,
      user_name: user.name,
      timestamp: timestamp.iso8601,
      changes: field_changes
    }
    
    update_column(:changes_log, change_log)
  end

  def modification_summary
    return "No modifications" unless changes_log.present?
    
    total_changes = changes_log.sum { |log| log["changes"]&.keys&.count || 0 }
    last_change = changes_log.last
    
    "#{total_changes} field(s) modified, last by #{last_change['user_name']} #{time_ago_in_words(Time.parse(last_change['timestamp']))} ago"
  end

  def confidence_improvement
    return 0 unless element.confidence_score.present?
    
    # Calculate confidence improvement based on user modifications
    base_confidence = element.confidence_score
    modification_boost = changes_log&.count || 0 * 0.05 # 5% boost per modification
    
    [base_confidence + modification_boost, 1.0].min
  end
end
```

### 3. Element Verification Migration
```ruby
# db/migrate/xxx_create_element_verifications.rb
class CreateElementVerifications < ActiveRecord::Migration[8.0]
  def change
    create_table :element_verifications do |t|
      t.references :element, null: false, foreign_key: true, index: { unique: true }
      t.references :verified_by, null: true, foreign_key: { to_table: :users }
      t.references :rejected_by, null: true, foreign_key: { to_table: :users }
      t.string :status, null: false, default: 'pending'
      t.datetime :verified_at
      t.datetime :rejected_at
      t.text :rejection_reason
      t.text :notes
      t.json :changes_log, default: []
      t.json :verification_metadata, default: {}

      t.timestamps
    end

    add_index :element_verifications, :status
    add_index :element_verifications, [:status, :created_at]
    add_index :element_verifications, :verified_at
  end
end
```

### 4. Verification Index View
```erb
<!-- app/views/projects/verifications/index.html.erb -->
<% content_for :title, "#{@project.title} - Verification" %>

<div class="min-h-screen bg-gray-50">
  <!-- Header -->
  <div class="bg-white shadow">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
      <div class="flex items-center justify-between py-6">
        <div class="flex items-center space-x-4">
          <%= link_to @project, class: "text-gray-400 hover:text-gray-600" do %>
            <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
            </svg>
          <% end %>
          <div>
            <h1 class="text-2xl font-bold text-gray-900">Verification</h1>
            <p class="text-sm text-gray-500">
              <%= link_to @project.title, @project, class: "hover:text-gray-700" %> • 
              Review AI-extracted element data
            </p>
          </div>
        </div>
        
        <div class="flex items-center space-x-3">
          <% if @pending_elements.any? %>
            <button class="btn btn-secondary" data-action="click->batch#toggleSelection">
              Batch Actions
            </button>
          <% end %>
        </div>
      </div>
    </div>
  </div>

  <!-- Stats -->
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
    <div id="verification_stats">
      <%= render "verification_stats", stats: @verification_stats %>
    </div>
  </div>

  <!-- Pending Verification -->
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 pb-8">
    <% if @pending_elements.any? %>
      <div class="mb-8">
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-lg font-medium text-gray-900">Pending Verification (<%= @pending_elements.count %>)</h2>
          
          <div id="batch_actions" class="hidden flex items-center space-x-3">
            <%= form_with url: batch_approve_project_verifications_path(@project), 
                method: :patch,
                data: { turbo_method: :patch },
                class: "flex items-center space-x-3" do |form| %>
              <input type="hidden" name="element_ids[]" id="selected_element_ids" value="">
              <%= form.submit "Approve Selected", class: "btn btn-success btn-sm" %>
            <% end %>
            <button class="btn btn-secondary btn-sm" data-action="click->batch#clearSelection">
              Cancel
            </button>
          </div>
        </div>

        <div class="space-y-4" data-controller="batch">
          <% @pending_elements.each do |element| %>
            <%= render "verification_card", element: element %>
          <% end %>
        </div>
      </div>
    <% else %>
      <div class="text-center py-12 bg-white rounded-lg shadow">
        <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>
        <h3 class="mt-2 text-sm font-medium text-gray-900">All caught up!</h3>
        <p class="mt-1 text-sm text-gray-500">
          No elements require verification at this time.
        </p>
      </div>
    <% end %>

    <!-- Recently Verified -->
    <% if @verified_elements.any? %>
      <div class="mt-8">
        <h2 class="text-lg font-medium text-gray-900 mb-4">Recently Verified</h2>
        <div class="bg-white shadow rounded-lg overflow-hidden">
          <ul class="divide-y divide-gray-200">
            <% @verified_elements.each do |element| %>
              <li class="px-6 py-4">
                <div class="flex items-center justify-between">
                  <div>
                    <p class="text-sm font-medium text-gray-900">
                      <%= link_to element.name, [element.project, element], class: "hover:text-blue-600" %>
                    </p>
                    <p class="text-sm text-gray-500"><%= element.element_type&.humanize %></p>
                  </div>
                  <div class="text-right">
                    <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                      Verified
                    </span>
                    <p class="text-xs text-gray-500 mt-1">
                      <%= time_ago_in_words(element.updated_at) %> ago
                    </p>
                  </div>
                </div>
              </li>
            <% end %>
          </ul>
        </div>
      </div>
    <% end %>
  </div>
</div>

<%= turbo_stream_from "project_#{@project.id}" %>
```

### 5. Verification Card Partial
```erb
<!-- app/views/projects/verifications/_verification_card.html.erb -->
<div id="element_<%= element.id %>" class="bg-white shadow rounded-lg p-6 hover:shadow-md transition-shadow">
  <div class="flex items-start justify-between">
    <div class="flex items-start space-x-4 flex-1">
      <div class="flex-shrink-0">
        <input type="checkbox" 
               class="mt-1 rounded border-gray-300 text-blue-600 focus:ring-blue-500" 
               data-batch-target="checkbox"
               data-element-id="<%= element.id %>">
      </div>
      
      <div class="flex-1 min-w-0">
        <div class="flex items-center space-x-3 mb-2">
          <h3 class="text-lg font-medium text-gray-900 truncate">
            <%= link_to element.name, project_verification_path(@project, element), 
                class: "hover:text-blue-600" %>
          </h3>
          
          <!-- Confidence Badge -->
          <% confidence = (element.confidence_score || 0) * 100 %>
          <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium 
                       <%= confidence >= 80 ? 'bg-green-100 text-green-800' : 
                           confidence >= 60 ? 'bg-yellow-100 text-yellow-800' : 
                                              'bg-red-100 text-red-800' %>">
            <%= number_to_percentage(confidence, precision: 0) %> confidence
          </span>
        </div>

        <p class="text-sm text-gray-600 mb-3 line-clamp-2">
          <%= element.specification_preview(100) %>
        </p>

        <!-- Extracted Parameters Summary -->
        <% if element.extracted_params.present? %>
          <div class="flex flex-wrap gap-2 mb-3">
            <% element.extracted_params.each do |category, params| %>
              <% next unless params.is_a?(Hash) && params.any? %>
              <span class="inline-flex items-center px-2 py-1 rounded text-xs bg-blue-50 text-blue-700">
                <%= category.humanize %>: <%= params.keys.count %> field<%= 's' if params.keys.count != 1 %>
              </span>
            <% end %>
          </div>
        <% end %>

        <!-- Issues/Warnings -->
        <% if element.confidence_score && element.confidence_score < 0.7 %>
          <div class="flex items-center space-x-2 text-sm text-amber-600">
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16c-.77.833.192 2.5 1.732 2.5z" />
            </svg>
            <span>Low confidence - manual review recommended</span>
          </div>
        <% end %>
      </div>
    </div>

    <!-- Actions -->
    <div class="flex items-center space-x-2">
      <%= link_to "Review", project_verification_path(@project, element),
          class: "btn btn-primary btn-sm" %>
      
      <%= link_to approve_project_verification_path(@project, element),
          method: :patch,
          class: "btn btn-success btn-sm",
          data: { 
            turbo_method: :patch,
            turbo_confirm: "Approve this element without detailed review?" 
          },
          title: "Quick approve" do %>
        <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
        </svg>
      <% end %>

      <%= link_to reject_project_verification_path(@project, element),
          method: :patch,
          class: "btn btn-danger btn-sm",
          data: { 
            turbo_method: :patch,
            turbo_confirm: "Reject this element? It will be queued for reprocessing." 
          },
          title: "Reject and reprocess" do %>
        <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
        </svg>
      <% end %>
    </div>
  </div>
</div>
```

### 6. Verification Stats Partial
```erb
<!-- app/views/projects/verifications/_verification_stats.html.erb -->
<div class="grid grid-cols-1 gap-5 sm:grid-cols-4">
  <div class="bg-white overflow-hidden shadow rounded-lg">
    <div class="p-5">
      <div class="flex items-center">
        <div class="flex-shrink-0">
          <div class="w-8 h-8 bg-blue-100 rounded-full flex items-center justify-center">
            <svg class="w-5 h-5 text-blue-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
            </svg>
          </div>
        </div>
        <div class="ml-5 w-0 flex-1">
          <dl>
            <dt class="text-sm font-medium text-gray-500 truncate">Pending Review</dt>
            <dd class="text-lg font-medium text-gray-900"><%= stats[:total_processed] %></dd>
          </dl>
        </div>
      </div>
    </div>
  </div>

  <div class="bg-white overflow-hidden shadow rounded-lg">
    <div class="p-5">
      <div class="flex items-center">
        <div class="flex-shrink-0">
          <div class="w-8 h-8 bg-green-100 rounded-full flex items-center justify-center">
            <svg class="w-5 h-5 text-green-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
          </div>
        </div>
        <div class="ml-5 w-0 flex-1">
          <dl>
            <dt class="text-sm font-medium text-gray-500 truncate">Verified</dt>
            <dd class="text-lg font-medium text-gray-900"><%= stats[:total_verified] %></dd>
          </dl>
        </div>
      </div>
    </div>
  </div>

  <div class="bg-white overflow-hidden shadow rounded-lg">
    <div class="p-5">
      <div class="flex items-center">
        <div class="flex-shrink-0">
          <div class="w-8 h-8 bg-purple-100 rounded-full flex items-center justify-center">
            <svg class="w-5 h-5 text-purple-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7h8m0 0v8m0-8l-8 8-4-4-6 6" />
            </svg>
          </div>
        </div>
        <div class="ml-5 w-0 flex-1">
          <dl>
            <dt class="text-sm font-medium text-gray-500 truncate">Completion Rate</dt>
            <dd class="text-lg font-medium text-gray-900"><%= stats[:completion_rate] %>%</dd>
          </dl>
        </div>
      </div>
    </div>
  </div>

  <div class="bg-white overflow-hidden shadow rounded-lg">
    <div class="p-5">
      <div class="flex items-center">
        <div class="flex-shrink-0">
          <div class="w-8 h-8 bg-indigo-100 rounded-full flex items-center justify-center">
            <svg class="w-5 h-5 text-indigo-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
            </svg>
          </div>
        </div>
        <div class="ml-5 w-0 flex-1">
          <dl>
            <dt class="text-sm font-medium text-gray-500 truncate">Avg Confidence</dt>
            <dd class="text-lg font-medium text-gray-900"><%= stats[:average_confidence] %>%</dd>
          </dl>
        </div>
      </div>
    </div>
  </div>
</div>
```

## Technical Notes
- Separates verification logic into dedicated controller and model
- Provides batch operations for efficiency with multiple elements
- Uses confidence scoring to prioritize review needs
- Tracks all user modifications for audit trail
- Real-time updates via Turbo Streams for collaborative verification
- Mobile-responsive design supports field verification workflows

## Definition of Done
- [ ] Verification interface displays pending elements correctly
- [ ] Parameter editing works with inline validation
- [ ] Confidence indicators provide clear guidance
- [ ] Batch operations function properly
- [ ] Audit trail tracks all modifications
- [ ] Real-time updates work via Turbo Streams
- [ ] Mobile responsive design functions correctly
- [ ] Test coverage exceeds 90%
- [ ] Code review completed