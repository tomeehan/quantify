# Ticket 2: Verification UI Components

**Epic**: M4 LLM Element Data Verification  
**Story Points**: 5  
**Dependencies**: 001-verification-interface.md

## Description
Create the user interface components for reviewing and verifying AI-extracted element data. Provide intuitive editing capabilities with confidence indicators and batch operations for efficient verification workflows.

## Acceptance Criteria
- [ ] Interactive verification dashboard with extracted data display
- [ ] Inline editing for all extracted parameters
- [ ] Confidence level indicators for AI extractions
- [ ] Batch approval/rejection operations
- [ ] Real-time updates via Hotwire
- [ ] Mobile-responsive verification interface
- [ ] Undo/redo functionality for edits

## Code to be Written

### 1. Verification Dashboard View
```erb
<!-- app/views/elements/verify.html.erb -->
<% content_for :title, "Verify AI Extractions - #{@project.title}" %>

<div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
  <div class="mb-8">
    <div class="flex items-center justify-between">
      <div>
        <h1 class="text-2xl font-bold text-gray-900">Verify AI Extractions</h1>
        <p class="mt-1 text-sm text-gray-500">
          Review and confirm the AI-extracted element data for accuracy
        </p>
      </div>
      
      <div class="flex space-x-3">
        <button type="button" 
                class="btn btn-secondary"
                data-controller="batch-operations"
                data-action="click->batch-operations#approveAll">
          Approve All High Confidence
        </button>
        <button type="button" class="btn btn-primary" id="save-changes">
          Save Changes
        </button>
      </div>
    </div>
    
    <!-- Progress Indicator -->
    <div class="mt-4">
      <div class="bg-gray-200 rounded-full h-2">
        <div class="bg-blue-600 h-2 rounded-full transition-all duration-300" 
             style="width: <%= (@verified_count.to_f / @total_count * 100).round(1) %>%"></div>
      </div>
      <p class="mt-1 text-xs text-gray-500">
        <%= @verified_count %> of <%= @total_count %> elements verified
      </p>
    </div>
  </div>

  <!-- Verification Grid -->
  <div class="space-y-6" data-controller="verification-grid">
    <% @elements.each do |element| %>
      <%= render "verification_card", element: element %>
    <% end %>
  </div>
</div>
```

### 2. Verification Card Component
```erb
<!-- app/views/elements/_verification_card.html.erb -->
<div class="bg-white rounded-lg border border-gray-200 shadow-sm"
     data-controller="verification-card"
     data-element-id="<%= element.id %>"
     data-verification-card-confidence-value="<%= element.extraction_confidence %>">
  
  <!-- Header with confidence indicator -->
  <div class="px-6 py-4 border-b border-gray-200">
    <div class="flex items-center justify-between">
      <div class="flex items-center space-x-3">
        <h3 class="text-lg font-medium text-gray-900"><%= element.name %></h3>
        <div class="flex items-center space-x-2">
          <%= render "confidence_badge", confidence: element.extraction_confidence %>
          <% if element.verification_status == "verified" %>
            <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
              Verified
            </span>
          <% end %>
        </div>
      </div>
      
      <div class="flex items-center space-x-2">
        <button type="button" 
                class="text-sm text-gray-500 hover:text-gray-700"
                data-action="click->verification-card#toggleOriginal">
          View Original
        </button>
        <button type="button" 
                class="text-sm text-blue-600 hover:text-blue-800"
                data-action="click->verification-card#reprocessWithAI">
          Re-process with AI
        </button>
      </div>
    </div>
  </div>

  <!-- Original specification (collapsible) -->
  <div class="hidden px-6 py-3 bg-gray-50 border-b border-gray-200" 
       data-verification-card-target="originalSpec">
    <h4 class="text-sm font-medium text-gray-700 mb-2">Original Specification:</h4>
    <p class="text-sm text-gray-600 whitespace-pre-line"><%= element.specification_text %></p>
  </div>

  <!-- Extracted Data Grid -->
  <div class="p-6">
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
      
      <!-- Type -->
      <div class="space-y-2">
        <label class="block text-sm font-medium text-gray-700">Element Type</label>
        <div class="relative">
          <%= text_field_tag "extracted_data[type]", 
                            element.extracted_data&.dig("type"),
                            class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm",
                            data: { 
                              verification_card_target: "typeField",
                              action: "input->verification-card#markAsEdited"
                            } %>
          <%= render "confidence_indicator", 
                     field: "type", 
                     confidence: element.field_confidence&.dig("type") %>
        </div>
      </div>

      <!-- Dimensions -->
      <div class="space-y-2">
        <label class="block text-sm font-medium text-gray-700">Dimensions</label>
        <div class="grid grid-cols-3 gap-2">
          <input type="text" 
                 placeholder="Length"
                 value="<%= element.extracted_data&.dig("dimensions", "length") %>"
                 class="block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                 data-action="input->verification-card#markAsEdited">
          <input type="text" 
                 placeholder="Width"
                 value="<%= element.extracted_data&.dig("dimensions", "width") %>"
                 class="block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                 data-action="input->verification-card#markAsEdited">
          <input type="text" 
                 placeholder="Height"
                 value="<%= element.extracted_data&.dig("dimensions", "height") %>"
                 class="block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                 data-action="input->verification-card#markAsEdited">
        </div>
        <%= render "confidence_indicator", 
                   field: "dimensions", 
                   confidence: element.field_confidence&.dig("dimensions") %>
      </div>

      <!-- Material -->
      <div class="space-y-2">
        <label class="block text-sm font-medium text-gray-700">Material</label>
        <div class="relative">
          <%= text_field_tag "extracted_data[material]", 
                            element.extracted_data&.dig("material"),
                            class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm",
                            data: { action: "input->verification-card#markAsEdited" } %>
          <%= render "confidence_indicator", 
                     field: "material", 
                     confidence: element.field_confidence&.dig("material") %>
        </div>
      </div>

      <!-- Finish -->
      <div class="space-y-2">
        <label class="block text-sm font-medium text-gray-700">Finish</label>
        <div class="relative">
          <%= text_field_tag "extracted_data[finish]", 
                            element.extracted_data&.dig("finish"),
                            class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm",
                            data: { action: "input->verification-card#markAsEdited" } %>
          <%= render "confidence_indicator", 
                     field: "finish", 
                     confidence: element.field_confidence&.dig("finish") %>
        </div>
      </div>

      <!-- Location -->
      <div class="space-y-2">
        <label class="block text-sm font-medium text-gray-700">Location</label>
        <div class="relative">
          <%= text_field_tag "extracted_data[location]", 
                            element.extracted_data&.dig("location"),
                            class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm",
                            data: { action: "input->verification-card#markAsEdited" } %>
          <%= render "confidence_indicator", 
                     field: "location", 
                     confidence: element.field_confidence&.dig("location") %>
        </div>
      </div>

      <!-- Details -->
      <div class="space-y-2">
        <label class="block text-sm font-medium text-gray-700">Additional Details</label>
        <div class="relative">
          <%= text_area_tag "extracted_data[details]", 
                           element.extracted_data&.dig("details"),
                           rows: 2,
                           class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm",
                           data: { action: "input->verification-card#markAsEdited" } %>
          <%= render "confidence_indicator", 
                     field: "details", 
                     confidence: element.field_confidence&.dig("details") %>
        </div>
      </div>
    </div>

    <!-- Action Buttons -->
    <div class="mt-6 flex items-center justify-between pt-4 border-t border-gray-200">
      <div class="flex items-center space-x-4">
        <button type="button" 
                class="inline-flex items-center px-3 py-2 border border-transparent text-sm leading-4 font-medium rounded-md text-white bg-green-600 hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
                data-action="click->verification-card#approve">
          <svg class="w-4 h-4 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
          </svg>
          Approve
        </button>
        
        <button type="button" 
                class="inline-flex items-center px-3 py-2 border border-gray-300 text-sm leading-4 font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                data-action="click->verification-card#requestClarification">
          <svg class="w-4 h-4 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8.228 9c.549-1.165 2.03-2 3.772-2 2.21 0 4 1.343 4 3 0 1.4-1.278 2.575-3.006 2.907-.542.104-.994.54-.994 1.093m0 3h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          Need Clarification
        </button>
      </div>

      <div class="text-xs text-gray-500" data-verification-card-target="lastModified">
        <% if element.updated_at != element.created_at %>
          Last modified <%= time_ago_in_words(element.updated_at) %> ago
        <% end %>
      </div>
    </div>
  </div>
</div>
```

### 3. Confidence Badge Component
```erb
<!-- app/views/elements/_confidence_badge.html.erb -->
<% 
  case confidence
  when 0.8..1.0
    badge_class = "bg-green-100 text-green-800"
    label = "High"
  when 0.6..0.79
    badge_class = "bg-yellow-100 text-yellow-800"
    label = "Medium"
  when 0.4..0.59
    badge_class = "bg-orange-100 text-orange-800"
    label = "Low"
  else
    badge_class = "bg-red-100 text-red-800"
    label = "Very Low"
  end
%>

<span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium <%= badge_class %>">
  <%= label %> (<%= (confidence * 100).round %>%)
</span>
```

### 4. Verification Card Stimulus Controller
```javascript
// app/javascript/controllers/verification_card_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["originalSpec", "typeField", "lastModified"]
  static values = { confidence: Number }

  connect() {
    this.hasChanges = false
    this.originalData = this.collectFormData()
  }

  toggleOriginal() {
    this.originalSpecTarget.classList.toggle("hidden")
  }

  markAsEdited() {
    this.hasChanges = true
    this.element.classList.add("border-yellow-300", "bg-yellow-50")
    this.updateLastModified()
  }

  approve() {
    if (this.hasChanges) {
      this.saveChanges().then(() => {
        this.markAsApproved()
      })
    } else {
      this.markAsApproved()
    }
  }

  markAsApproved() {
    this.element.classList.remove("border-yellow-300", "bg-yellow-50")
    this.element.classList.add("border-green-300", "bg-green-50")
    
    // Add verified badge
    const header = this.element.querySelector('.border-b')
    if (!header.querySelector('.bg-green-100')) {
      const badge = document.createElement('span')
      badge.className = "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800"
      badge.textContent = "Verified"
      header.querySelector('.flex.items-center.space-x-2').appendChild(badge)
    }
  }

  requestClarification() {
    // Open clarification modal or form
    const modal = document.createElement('div')
    modal.innerHTML = this.clarificationModalHTML()
    document.body.appendChild(modal)
  }

  reprocessWithAI() {
    // Trigger re-processing
    this.element.classList.add("opacity-50")
    
    fetch(`/projects/${this.data.get("projectId")}/elements/${this.data.get("elementId")}/reprocess`, {
      method: "POST",
      headers: {
        "X-CSRF-Token": document.querySelector("[name='csrf-token']").content,
        "Content-Type": "application/json"
      }
    }).then(response => {
      if (response.ok) {
        location.reload() // Refresh to show new extractions
      }
    })
  }

  saveChanges() {
    const formData = this.collectFormData()
    
    return fetch(`/projects/${this.data.get("projectId")}/elements/${this.data.get("elementId")}/update_extraction`, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": document.querySelector("[name='csrf-token']").content,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({ extracted_data: formData })
    }).then(response => {
      if (response.ok) {
        this.hasChanges = false
        this.originalData = formData
        this.updateLastModified()
        return response.json()
      }
    })
  }

  collectFormData() {
    const inputs = this.element.querySelectorAll('input, textarea, select')
    const data = {}
    
    inputs.forEach(input => {
      if (input.name.startsWith('extracted_data[')) {
        const fieldName = input.name.match(/\[(.*?)\]/)[1]
        data[fieldName] = input.value
      }
    })
    
    return data
  }

  updateLastModified() {
    if (this.hasLastModifiedTarget) {
      this.lastModifiedTarget.textContent = "Modified just now"
    }
  }

  clarificationModalHTML() {
    return `
      <div class="fixed inset-0 bg-gray-500 bg-opacity-75 flex items-center justify-center p-4 z-50">
        <div class="bg-white rounded-lg shadow-xl max-w-md w-full">
          <div class="px-6 py-4">
            <h3 class="text-lg font-medium text-gray-900">Request Clarification</h3>
            <textarea class="mt-3 block w-full rounded-md border-gray-300 shadow-sm" 
                      rows="4" 
                      placeholder="What needs clarification about this element?"></textarea>
            <div class="mt-4 flex justify-end space-x-3">
              <button type="button" class="btn btn-secondary" onclick="this.closest('.fixed').remove()">
                Cancel
              </button>
              <button type="button" class="btn btn-primary">
                Send Request
              </button>
            </div>
          </div>
        </div>
      </div>
    `
  }
}
```

## Technical Notes
- Uses Stimulus for rich client-side interactions
- Real-time confidence indicators guide user focus
- Batch operations for efficient verification workflows
- Inline editing with automatic change tracking
- Mobile-responsive grid layout adapts to screen size

## Definition of Done
- [ ] Verification dashboard displays all elements
- [ ] Inline editing works for all extracted fields
- [ ] Confidence indicators show appropriate colors
- [ ] Batch operations function correctly
- [ ] Mobile responsive design works well
- [ ] Auto-save functionality prevents data loss
- [ ] Code review completed