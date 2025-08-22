# Ticket 3: Batch Operations & Audit Trail

**Epic**: M4 LLM Element Data Verification  
**Story Points**: 3  
**Dependencies**: 002-verification-ui.md

## Description
Implement batch operations for efficient verification workflows and comprehensive audit trails for all verification activities. Enable bulk approval, rejection, and modification tracking.

## Acceptance Criteria
- [ ] Batch approve/reject operations for multiple elements
- [ ] Filter elements by confidence level for targeted review
- [ ] Complete audit trail of all verification activities
- [ ] Bulk edit capabilities for similar elements
- [ ] Export verification reports
- [ ] User permission controls for batch operations

## Code to be Written

### 1. Batch Operations Controller
```ruby
# app/controllers/elements/batch_operations_controller.rb
class Elements::BatchOperationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_project

  def approve_batch
    authorize Element, :batch_update?
    
    element_ids = params[:element_ids]
    elements = @project.elements.where(id: element_ids)
    
    ActiveRecord::Base.transaction do
      elements.find_each do |element|
        element.update!(
          verification_status: "approved",
          verified_by: current_user,
          verified_at: Time.current
        )
        
        create_audit_entry(element, "batch_approved")
      end
    end

    render json: { 
      success: true, 
      message: "#{elements.count} elements approved successfully" 
    }
  rescue => error
    render json: { 
      success: false, 
      message: "Batch approval failed: #{error.message}" 
    }, status: :unprocessable_entity
  end

  def reject_batch
    authorize Element, :batch_update?
    
    element_ids = params[:element_ids]
    rejection_reason = params[:rejection_reason]
    elements = @project.elements.where(id: element_ids)
    
    ActiveRecord::Base.transaction do
      elements.find_each do |element|
        element.update!(
          verification_status: "rejected",
          verification_notes: rejection_reason,
          verified_by: current_user,
          verified_at: Time.current
        )
        
        create_audit_entry(element, "batch_rejected", { reason: rejection_reason })
      end
    end

    render json: { 
      success: true, 
      message: "#{elements.count} elements rejected successfully" 
    }
  end

  def bulk_edit
    authorize Element, :batch_update?
    
    element_ids = params[:element_ids]
    field_updates = params[:field_updates]
    elements = @project.elements.where(id: element_ids)
    
    ActiveRecord::Base.transaction do
      elements.find_each do |element|
        updated_data = element.extracted_data.deep_merge(field_updates)
        element.update!(extracted_data: updated_data)
        
        create_audit_entry(element, "bulk_edited", { 
          fields_updated: field_updates.keys,
          updates: field_updates 
        })
      end
    end

    render json: { 
      success: true, 
      message: "#{elements.count} elements updated successfully" 
    }
  end

  def export_verification_report
    authorize @project, :show?
    
    report_data = generate_verification_report
    
    respond_to do |format|
      format.csv { send_data report_data[:csv], filename: "verification_report_#{Date.current}.csv" }
      format.json { render json: report_data[:json] }
    end
  end

  private

  def set_project
    @project = current_account.projects.find(params[:project_id])
  end

  def create_audit_entry(element, action, metadata = {})
    VerificationAudit.create!(
      element: element,
      user: current_user,
      action: action,
      metadata: metadata.merge({
        timestamp: Time.current.iso8601,
        user_agent: request.user_agent,
        ip_address: request.remote_ip
      })
    )
  end

  def generate_verification_report
    elements = @project.elements.includes(:verification_audits)
    
    csv_data = CSV.generate(headers: true) do |csv|
      csv << [
        "Element Name", "Verification Status", "Confidence Score", 
        "Verified By", "Verified At", "Extraction Accuracy", "Notes"
      ]
      
      elements.each do |element|
        csv << [
          element.name,
          element.verification_status,
          element.extraction_confidence,
          element.verified_by&.name,
          element.verified_at&.strftime("%Y-%m-%d %H:%M"),
          calculate_extraction_accuracy(element),
          element.verification_notes
        ]
      end
    end

    json_data = {
      project: @project.title,
      generated_at: Time.current.iso8601,
      total_elements: elements.count,
      verification_summary: {
        approved: elements.where(verification_status: "approved").count,
        rejected: elements.where(verification_status: "rejected").count,
        pending: elements.where(verification_status: "pending").count
      },
      elements: elements.map { |e| element_verification_summary(e) }
    }

    { csv: csv_data, json: json_data }
  end

  def calculate_extraction_accuracy(element)
    return "N/A" unless element.verified?
    
    # Compare original AI extraction with verified data
    original = element.ai_extraction_history.last&.dig("extracted_data") || {}
    verified = element.extracted_data || {}
    
    total_fields = verified.keys.count
    unchanged_fields = verified.count { |k, v| original[k] == v }
    
    return "N/A" if total_fields.zero?
    
    "#{((unchanged_fields.to_f / total_fields) * 100).round(1)}%"
  end

  def element_verification_summary(element)
    {
      id: element.id,
      name: element.name,
      verification_status: element.verification_status,
      confidence: element.extraction_confidence,
      verified_by: element.verified_by&.name,
      verified_at: element.verified_at&.iso8601,
      audit_trail: element.verification_audits.map { |audit|
        {
          action: audit.action,
          user: audit.user.name,
          timestamp: audit.created_at.iso8601,
          metadata: audit.metadata
        }
      }
    }
  end
end
```

### 2. Verification Audit Model
```ruby
# app/models/verification_audit.rb
class VerificationAudit < ApplicationRecord
  belongs_to :element
  belongs_to :user

  validates :action, presence: true
  validates :metadata, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :for_action, ->(action) { where(action: action) }

  enum action: {
    ai_extracted: 0,
    manually_edited: 1,
    approved: 2,
    rejected: 3,
    batch_approved: 4,
    batch_rejected: 5,
    bulk_edited: 6,
    reprocessed: 7
  }

  def summary
    case action
    when "ai_extracted"
      "AI extracted data with #{metadata['confidence']}% confidence"
    when "manually_edited"
      "User edited #{metadata['fields_changed']&.join(', ')}"
    when "approved"
      "Approved by #{user.name}"
    when "rejected"
      "Rejected: #{metadata['reason']}"
    when "batch_approved"
      "Batch approved by #{user.name}"
    when "batch_rejected"
      "Batch rejected: #{metadata['reason']}"
    when "bulk_edited"
      "Bulk edited #{metadata['fields_updated']&.join(', ')}"
    when "reprocessed"
      "Reprocessed with AI"
    else
      "#{action.humanize} by #{user.name}"
    end
  end
end
```

### 3. Migration for Verification Audit
```ruby
# db/migrate/xxx_create_verification_audits.rb
class CreateVerificationAudits < ActiveRecord::Migration[8.0]
  def change
    create_table :verification_audits do |t|
      t.references :element, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :action, null: false
      t.json :metadata, null: false

      t.timestamps
    end

    add_index :verification_audits, :element_id
    add_index :verification_audits, :user_id
    add_index :verification_audits, :action
    add_index :verification_audits, [:element_id, :created_at]
  end
end
```

### 4. Batch Operations UI
```erb
<!-- app/views/elements/_batch_operations_toolbar.html.erb -->
<div class="bg-blue-50 border border-blue-200 rounded-lg p-4 mb-6" 
     data-controller="batch-operations"
     style="display: none;"
     data-batch-operations-target="toolbar">
  
  <div class="flex items-center justify-between">
    <div class="flex items-center space-x-4">
      <span class="text-sm font-medium text-blue-900">
        <span data-batch-operations-target="selectedCount">0</span> elements selected
      </span>
      
      <div class="flex items-center space-x-2">
        <button type="button" 
                class="inline-flex items-center px-3 py-1.5 border border-transparent text-xs font-medium rounded text-white bg-green-600 hover:bg-green-700"
                data-action="click->batch-operations#approveSelected">
          <svg class="w-3 h-3 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
          </svg>
          Approve All
        </button>
        
        <button type="button" 
                class="inline-flex items-center px-3 py-1.5 border border-gray-300 text-xs font-medium rounded text-gray-700 bg-white hover:bg-gray-50"
                data-action="click->batch-operations#showRejectModal">
          <svg class="w-3 h-3 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
          </svg>
          Reject All
        </button>
        
        <button type="button" 
                class="inline-flex items-center px-3 py-1.5 border border-gray-300 text-xs font-medium rounded text-gray-700 bg-white hover:bg-gray-50"
                data-action="click->batch-operations#showBulkEditModal">
          <svg class="w-3 h-3 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z" />
          </svg>
          Bulk Edit
        </button>
      </div>
    </div>
    
    <div class="flex items-center space-x-2">
      <button type="button" 
              class="text-xs text-gray-500 hover:text-gray-700"
              data-action="click->batch-operations#selectByConfidence"
              data-confidence="high">
        Select High Confidence
      </button>
      
      <button type="button" 
              class="text-xs text-gray-500 hover:text-gray-700"
              data-action="click->batch-operations#clearSelection">
        Clear Selection
      </button>
    </div>
  </div>
</div>
```

### 5. Batch Operations Stimulus Controller
```javascript
// app/javascript/controllers/batch_operations_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toolbar", "selectedCount"]

  connect() {
    this.selectedElements = new Set()
    document.addEventListener("element-selection-changed", this.handleSelectionChange.bind(this))
  }

  disconnect() {
    document.removeEventListener("element-selection-changed", this.handleSelectionChange.bind(this))
  }

  handleSelectionChange(event) {
    const { elementId, selected } = event.detail
    
    if (selected) {
      this.selectedElements.add(elementId)
    } else {
      this.selectedElements.delete(elementId)
    }
    
    this.updateToolbar()
  }

  updateToolbar() {
    const count = this.selectedElements.size
    this.selectedCountTarget.textContent = count
    
    if (count > 0) {
      this.toolbarTarget.style.display = "block"
    } else {
      this.toolbarTarget.style.display = "none"
    }
  }

  approveSelected() {
    const elementIds = Array.from(this.selectedElements)
    
    this.performBatchOperation("approve_batch", { element_ids: elementIds })
  }

  showRejectModal() {
    const modal = this.createRejectModal()
    document.body.appendChild(modal)
  }

  showBulkEditModal() {
    const modal = this.createBulkEditModal()
    document.body.appendChild(modal)
  }

  selectByConfidence(event) {
    const confidence = event.currentTarget.dataset.confidence
    const elements = document.querySelectorAll("[data-verification-card-confidence-value]")
    
    elements.forEach(element => {
      const elementConfidence = parseFloat(element.dataset.verificationCardConfidenceValue)
      const shouldSelect = (confidence === "high" && elementConfidence >= 0.8) ||
                          (confidence === "medium" && elementConfidence >= 0.6 && elementConfidence < 0.8) ||
                          (confidence === "low" && elementConfidence < 0.6)
      
      if (shouldSelect) {
        const checkbox = element.querySelector('input[type="checkbox"]')
        if (checkbox) {
          checkbox.checked = true
          checkbox.dispatchEvent(new Event('change'))
        }
      }
    })
  }

  clearSelection() {
    document.querySelectorAll('.verification-card input[type="checkbox"]:checked').forEach(checkbox => {
      checkbox.checked = false
      checkbox.dispatchEvent(new Event('change'))
    })
  }

  async performBatchOperation(action, data) {
    try {
      const response = await fetch(`/projects/${this.data.get("projectId")}/elements/batch_operations/${action}`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector("[name='csrf-token']").content
        },
        body: JSON.stringify(data)
      })

      const result = await response.json()
      
      if (result.success) {
        this.showSuccessMessage(result.message)
        location.reload() // Refresh to show updated states
      } else {
        this.showErrorMessage(result.message)
      }
    } catch (error) {
      this.showErrorMessage("Operation failed: " + error.message)
    }
  }

  createRejectModal() {
    const modal = document.createElement('div')
    modal.className = "fixed inset-0 bg-gray-500 bg-opacity-75 flex items-center justify-center p-4 z-50"
    modal.innerHTML = `
      <div class="bg-white rounded-lg shadow-xl max-w-md w-full">
        <div class="px-6 py-4">
          <h3 class="text-lg font-medium text-gray-900">Reject Selected Elements</h3>
          <p class="mt-2 text-sm text-gray-500">
            Please provide a reason for rejecting these ${this.selectedElements.size} elements.
          </p>
          <textarea class="mt-3 block w-full rounded-md border-gray-300 shadow-sm" 
                    rows="3" 
                    placeholder="Reason for rejection..."
                    id="rejection-reason"></textarea>
          <div class="mt-4 flex justify-end space-x-3">
            <button type="button" class="btn btn-secondary" onclick="this.closest('.fixed').remove()">
              Cancel
            </button>
            <button type="button" class="btn btn-danger" onclick="this.rejectWithReason()">
              Reject Elements
            </button>
          </div>
        </div>
      </div>
    `
    
    modal.querySelector('.btn-danger').onclick = () => {
      const reason = modal.querySelector('#rejection-reason').value
      if (reason.trim()) {
        this.performBatchOperation("reject_batch", {
          element_ids: Array.from(this.selectedElements),
          rejection_reason: reason
        })
        modal.remove()
      }
    }
    
    return modal
  }

  createBulkEditModal() {
    const modal = document.createElement('div')
    modal.className = "fixed inset-0 bg-gray-500 bg-opacity-75 flex items-center justify-center p-4 z-50"
    modal.innerHTML = `
      <div class="bg-white rounded-lg shadow-xl max-w-lg w-full">
        <div class="px-6 py-4">
          <h3 class="text-lg font-medium text-gray-900">Bulk Edit Elements</h3>
          <p class="mt-2 text-sm text-gray-500">
            Apply changes to ${this.selectedElements.size} selected elements.
          </p>
          
          <div class="mt-4 space-y-4">
            <div>
              <label class="block text-sm font-medium text-gray-700">Material</label>
              <input type="text" id="bulk-material" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm">
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-700">Finish</label>
              <input type="text" id="bulk-finish" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm">
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-700">Location</label>
              <input type="text" id="bulk-location" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm">
            </div>
          </div>
          
          <div class="mt-6 flex justify-end space-x-3">
            <button type="button" class="btn btn-secondary" onclick="this.closest('.fixed').remove()">
              Cancel
            </button>
            <button type="button" class="btn btn-primary" onclick="this.applyBulkEdit()">
              Apply Changes
            </button>
          </div>
        </div>
      </div>
    `
    
    modal.querySelector('.btn-primary').onclick = () => {
      const updates = {}
      const material = modal.querySelector('#bulk-material').value
      const finish = modal.querySelector('#bulk-finish').value
      const location = modal.querySelector('#bulk-location').value
      
      if (material) updates.material = material
      if (finish) updates.finish = finish
      if (location) updates.location = location
      
      if (Object.keys(updates).length > 0) {
        this.performBatchOperation("bulk_edit", {
          element_ids: Array.from(this.selectedElements),
          field_updates: updates
        })
        modal.remove()
      }
    }
    
    return modal
  }

  showSuccessMessage(message) {
    // Implement toast notification
    console.log("Success:", message)
  }

  showErrorMessage(message) {
    // Implement error notification
    console.error("Error:", message)
  }
}
```

## Technical Notes
- Comprehensive audit trail tracks all verification activities
- Batch operations support efficient review workflows
- Export capabilities provide reporting and compliance features
- Permission controls ensure appropriate access to batch operations
- Transaction safety prevents partial updates during batch operations

## Definition of Done
- [ ] Batch approve/reject operations work correctly
- [ ] Audit trail captures all verification activities
- [ ] Export functionality generates accurate reports
- [ ] Bulk edit operations update multiple elements safely
- [ ] UI provides clear feedback for batch operations
- [ ] Permission controls prevent unauthorized access
- [ ] Code review completed