# Ticket 2: NRM Lookup Interface

**Epic**: M5 NRM Database Integration  
**Story Points**: 4  
**Dependencies**: 001-nrm-models.md

## Description
Create an intelligent NRM lookup interface that provides AI-powered suggestions and allows users to search, browse, and select appropriate NRM codes for their building elements.

## Acceptance Criteria
- [ ] Search interface for NRM codes with autocomplete
- [ ] AI-powered NRM suggestions based on element data
- [ ] Hierarchical NRM code browser with categories
- [ ] Quick selection workflow for common codes
- [ ] Preview of NRM code requirements and rules
- [ ] Bulk NRM code assignment for similar elements

## Code to be Written

### 1. NRM Lookup Controller
```ruby
# app/controllers/nrm_lookup_controller.rb
class NrmLookupController < ApplicationController
  before_action :authenticate_user!

  def search
    query = params[:query]
    element_data = params[:element_data]
    
    results = {
      text_matches: search_by_text(query),
      ai_suggestions: ai_suggest_nrm_codes(element_data),
      popular_codes: popular_nrm_codes_for_account
    }
    
    render json: results
  end

  def suggest
    element_id = params[:element_id]
    element = current_account.projects.joins(:elements).find(element_id)
    
    authorize element, :show?
    
    suggestions = NrmSuggestionService.new(element).generate_suggestions
    
    render json: {
      suggestions: suggestions,
      confidence_scores: suggestions.map { |s| s[:confidence] },
      reasoning: suggestions.map { |s| s[:reasoning] }
    }
  end

  def browse
    category = params[:category]
    subcategory = params[:subcategory]
    
    nrm_items = NrmItem.includes(:subcategory, :category)
    
    if category.present?
      nrm_items = nrm_items.joins(:category).where(nrm_categories: { code: category })
    end
    
    if subcategory.present?
      nrm_items = nrm_items.joins(:subcategory).where(nrm_subcategories: { code: subcategory })
    end
    
    render json: {
      items: nrm_items.limit(50).map { |item| nrm_item_summary(item) },
      categories: NrmCategory.order(:sort_order),
      subcategories: category.present? ? NrmSubcategory.where(category_code: category).order(:sort_order) : []
    }
  end

  def code_details
    nrm_code = params[:nrm_code]
    nrm_item = NrmItem.find_by(code: nrm_code)
    
    if nrm_item
      render json: {
        item: detailed_nrm_item(nrm_item),
        measurement_rules: nrm_item.measurement_rules,
        common_assemblies: nrm_item.assemblies.commonly_used,
        related_codes: find_related_nrm_codes(nrm_item)
      }
    else
      render json: { error: "NRM code not found" }, status: :not_found
    end
  end

  def assign_code
    element_id = params[:element_id]
    nrm_code = params[:nrm_code]
    confidence = params[:confidence] || "manual"
    
    element = current_account.projects.joins(:elements).find(element_id)
    authorize element, :update?
    
    nrm_item = NrmItem.find_by(code: nrm_code)
    
    if nrm_item && element.update(nrm_item: nrm_item, nrm_assignment_method: confidence)
      NrmAssignmentAudit.create!(
        element: element,
        nrm_item: nrm_item,
        assigned_by: current_user,
        assignment_method: confidence,
        metadata: {
          previous_nrm_code: element.nrm_item_was&.code,
          timestamp: Time.current
        }
      )
      
      render json: { success: true, message: "NRM code assigned successfully" }
    else
      render json: { success: false, message: "Failed to assign NRM code" }, status: :unprocessable_entity
    end
  end

  private

  def search_by_text(query)
    return [] if query.blank?
    
    NrmItem.search_by_text(query).limit(20).map { |item| nrm_item_summary(item) }
  end

  def ai_suggest_nrm_codes(element_data)
    return [] if element_data.blank?
    
    suggestions = NrmAiSuggestionService.new.suggest_codes(element_data)
    suggestions.map { |suggestion|
      nrm_item_summary(suggestion[:nrm_item]).merge(
        confidence: suggestion[:confidence],
        reasoning: suggestion[:reasoning]
      )
    }
  end

  def popular_nrm_codes_for_account
    # Get most used NRM codes for this account
    popular_codes = current_account.projects
                                  .joins(elements: :nrm_item)
                                  .group("nrm_items.id")
                                  .order("COUNT(*) DESC")
                                  .limit(10)
                                  .includes(:nrm_item)
                                  .pluck("nrm_items.id")
    
    NrmItem.where(id: popular_codes).map { |item| nrm_item_summary(item) }
  end

  def nrm_item_summary(nrm_item)
    {
      id: nrm_item.id,
      code: nrm_item.code,
      title: nrm_item.title,
      category: nrm_item.category&.name,
      subcategory: nrm_item.subcategory&.name,
      unit: nrm_item.unit,
      description: nrm_item.description&.truncate(200)
    }
  end

  def detailed_nrm_item(nrm_item)
    nrm_item_summary(nrm_item).merge(
      full_description: nrm_item.description,
      measurement_rules: nrm_item.measurement_rules,
      includes: nrm_item.includes,
      excludes: nrm_item.excludes,
      notes: nrm_item.notes,
      effective_date: nrm_item.effective_date,
      superseded_by: nrm_item.superseded_by&.code
    )
  end

  def find_related_nrm_codes(nrm_item)
    # Find related codes in same category/subcategory
    related = NrmItem.where(
      category: nrm_item.category,
      subcategory: nrm_item.subcategory
    ).where.not(id: nrm_item.id).limit(5)
    
    related.map { |item| nrm_item_summary(item) }
  end
end
```

### 2. NRM Lookup Interface Component
```erb
<!-- app/views/elements/_nrm_lookup_modal.html.erb -->
<div class="fixed inset-0 bg-gray-500 bg-opacity-75 flex items-center justify-center p-4 z-50"
     data-controller="nrm-lookup"
     data-nrm-lookup-element-id-value="<%= element.id %>"
     data-nrm-lookup-project-id-value="<%= element.project.id %>">
  
  <div class="bg-white rounded-lg shadow-xl max-w-4xl w-full max-h-screen overflow-hidden">
    <!-- Modal Header -->
    <div class="px-6 py-4 border-b border-gray-200">
      <div class="flex items-center justify-between">
        <div>
          <h3 class="text-lg font-medium text-gray-900">Select NRM Code</h3>
          <p class="mt-1 text-sm text-gray-500">
            Choose the appropriate NRM code for: <strong><%= element.name %></strong>
          </p>
        </div>
        <button type="button" 
                class="text-gray-400 hover:text-gray-600"
                data-action="click->nrm-lookup#close">
          <svg class="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>

      <!-- Search Bar -->
      <div class="mt-4">
        <div class="relative">
          <input type="text" 
                 placeholder="Search NRM codes by keyword, description, or code..."
                 class="block w-full pl-10 pr-3 py-2 border border-gray-300 rounded-md leading-5 bg-white placeholder-gray-500 focus:outline-none focus:placeholder-gray-400 focus:ring-1 focus:ring-blue-500 focus:border-blue-500"
                 data-nrm-lookup-target="searchInput"
                 data-action="input->nrm-lookup#performSearch">
          <div class="absolute inset-y-0 left-0 pl-3 flex items-center">
            <svg class="h-5 w-5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
            </svg>
          </div>
        </div>
      </div>

      <!-- Tabs -->
      <div class="mt-4">
        <nav class="flex space-x-8" aria-label="Tabs">
          <button type="button"
                  class="border-blue-500 text-blue-600 whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm"
                  data-nrm-lookup-target="tabButton"
                  data-tab="suggestions"
                  data-action="click->nrm-lookup#switchTab">
            AI Suggestions
          </button>
          <button type="button"
                  class="border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300 whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm"
                  data-nrm-lookup-target="tabButton"
                  data-tab="browse"
                  data-action="click->nrm-lookup#switchTab">
            Browse Categories
          </button>
          <button type="button"
                  class="border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300 whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm"
                  data-nrm-lookup-target="tabButton"
                  data-tab="popular"
                  data-action="click->nrm-lookup#switchTab">
            Popular Codes
          </button>
        </nav>
      </div>
    </div>

    <!-- Modal Body -->
    <div class="px-6 py-4 max-h-96 overflow-y-auto">
      
      <!-- AI Suggestions Tab -->
      <div data-nrm-lookup-target="tabContent" data-tab="suggestions">
        <div class="space-y-3" data-nrm-lookup-target="suggestionsContainer">
          <div class="text-center py-8">
            <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600 mx-auto"></div>
            <p class="mt-2 text-sm text-gray-500">Generating AI suggestions...</p>
          </div>
        </div>
      </div>

      <!-- Browse Categories Tab -->
      <div class="hidden" data-nrm-lookup-target="tabContent" data-tab="browse">
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <h4 class="text-sm font-medium text-gray-700 mb-3">Categories</h4>
            <div class="space-y-1" data-nrm-lookup-target="categoriesContainer">
              <!-- Categories will be loaded here -->
            </div>
          </div>
          <div>
            <h4 class="text-sm font-medium text-gray-700 mb-3">NRM Items</h4>
            <div class="space-y-1" data-nrm-lookup-target="itemsContainer">
              <!-- Items will be loaded here -->
            </div>
          </div>
        </div>
      </div>

      <!-- Popular Codes Tab -->
      <div class="hidden" data-nrm-lookup-target="tabContent" data-tab="popular">
        <div class="grid grid-cols-1 gap-3" data-nrm-lookup-target="popularContainer">
          <!-- Popular codes will be loaded here -->
        </div>
      </div>

      <!-- Search Results -->
      <div class="hidden" data-nrm-lookup-target="searchResults">
        <h4 class="text-sm font-medium text-gray-700 mb-3">Search Results</h4>
        <div class="space-y-2" data-nrm-lookup-target="searchResultsContainer">
          <!-- Search results will be loaded here -->
        </div>
      </div>
    </div>

    <!-- Modal Footer -->
    <div class="px-6 py-4 border-t border-gray-200 bg-gray-50">
      <div class="flex items-center justify-between">
        <div class="text-xs text-gray-500">
          <span data-nrm-lookup-target="selectedCodeInfo"></span>
        </div>
        <div class="flex space-x-3">
          <button type="button" 
                  class="btn btn-secondary"
                  data-action="click->nrm-lookup#close">
            Cancel
          </button>
          <button type="button" 
                  class="btn btn-primary"
                  data-nrm-lookup-target="assignButton"
                  data-action="click->nrm-lookup#assignSelectedCode"
                  disabled>
            Assign NRM Code
          </button>
        </div>
      </div>
    </div>
  </div>
</div>
```

### 3. NRM Item Card Component
```erb
<!-- app/views/nrm_lookup/_nrm_item_card.html.erb -->
<div class="border border-gray-200 rounded-lg p-4 hover:border-blue-300 hover:bg-blue-50 cursor-pointer transition-colors"
     data-controller="nrm-item-card"
     data-nrm-code="<%= nrm_item[:code] %>"
     data-action="click->nrm-item-card#select click->nrm-lookup#selectCode">
  
  <div class="flex items-start justify-between">
    <div class="flex-1 min-w-0">
      <div class="flex items-center space-x-2 mb-2">
        <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
          <%= nrm_item[:code] %>
        </span>
        <% if nrm_item[:confidence] %>
          <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
            <%= (nrm_item[:confidence] * 100).round %>% match
          </span>
        <% end %>
      </div>
      
      <h4 class="text-sm font-medium text-gray-900 mb-1">
        <%= nrm_item[:title] %>
      </h4>
      
      <p class="text-xs text-gray-600 mb-2">
        <%= nrm_item[:category] %> › <%= nrm_item[:subcategory] %>
      </p>
      
      <% if nrm_item[:description] %>
        <p class="text-xs text-gray-500 line-clamp-2">
          <%= nrm_item[:description] %>
        </p>
      <% end %>
      
      <% if nrm_item[:reasoning] %>
        <div class="mt-2 p-2 bg-blue-50 rounded text-xs text-blue-800">
          <strong>AI Reasoning:</strong> <%= nrm_item[:reasoning] %>
        </div>
      <% end %>
    </div>
    
    <div class="flex-shrink-0 ml-4">
      <span class="text-xs text-gray-500">
        Unit: <%= nrm_item[:unit] %>
      </span>
    </div>
  </div>
  
  <!-- Selection indicator -->
  <div class="hidden mt-3 pt-3 border-t border-blue-200" data-nrm-item-card-target="selectedIndicator">
    <div class="flex items-center text-xs text-blue-600">
      <svg class="w-4 h-4 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
      </svg>
      Selected
    </div>
  </div>
</div>
```

### 4. NRM Lookup Stimulus Controller
```javascript
// app/javascript/controllers/nrm_lookup_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "searchInput", "tabButton", "tabContent", "suggestionsContainer",
    "categoriesContainer", "itemsContainer", "popularContainer", 
    "searchResults", "searchResultsContainer", "selectedCodeInfo", "assignButton"
  ]
  static values = { elementId: Number, projectId: Number }

  connect() {
    this.selectedCode = null
    this.currentTab = "suggestions"
    this.loadAISuggestions()
    this.loadPopularCodes()
  }

  close() {
    this.element.remove()
  }

  switchTab(event) {
    const tab = event.currentTarget.dataset.tab
    this.currentTab = tab

    // Update tab buttons
    this.tabButtonTargets.forEach(button => {
      button.classList.remove("border-blue-500", "text-blue-600")
      button.classList.add("border-transparent", "text-gray-500")
    })
    event.currentTarget.classList.add("border-blue-500", "text-blue-600")
    event.currentTarget.classList.remove("border-transparent", "text-gray-500")

    // Update tab content
    this.tabContentTargets.forEach(content => {
      if (content.dataset.tab === tab) {
        content.classList.remove("hidden")
      } else {
        content.classList.add("hidden")
      }
    })

    // Load content if needed
    if (tab === "browse" && this.categoriesContainer.children.length === 0) {
      this.loadCategories()
    }
  }

  performSearch() {
    const query = this.searchInputTarget.value.trim()
    
    if (query.length < 2) {
      this.searchResultsTarget.classList.add("hidden")
      return
    }

    this.searchResultsTarget.classList.remove("hidden")
    this.searchResultsContainerTarget.innerHTML = '<div class="text-center py-4"><div class="animate-spin rounded-full h-6 w-6 border-b-2 border-blue-600 mx-auto"></div></div>'

    fetch(`/nrm_lookup/search?query=${encodeURIComponent(query)}`, {
      headers: { "Accept": "application/json" }
    })
    .then(response => response.json())
    .then(data => {
      this.renderSearchResults(data.text_matches)
    })
    .catch(error => {
      console.error("Search failed:", error)
      this.searchResultsContainerTarget.innerHTML = '<div class="text-center py-4 text-red-600">Search failed</div>'
    })
  }

  selectCode(event) {
    const card = event.currentTarget
    const nrmCode = card.dataset.nrmCode

    // Clear previous selection
    this.element.querySelectorAll('.border-blue-500').forEach(el => {
      el.classList.remove('border-blue-500', 'bg-blue-100')
      el.classList.add('border-gray-200')
      el.querySelector('[data-nrm-item-card-target="selectedIndicator"]')?.classList.add('hidden')
    })

    // Mark new selection
    card.classList.add('border-blue-500', 'bg-blue-100')
    card.classList.remove('border-gray-200')
    card.querySelector('[data-nrm-item-card-target="selectedIndicator"]')?.classList.remove('hidden')

    this.selectedCode = nrmCode
    this.selectedCodeInfoTarget.textContent = `Selected: ${nrmCode}`
    this.assignButtonTarget.disabled = false

    // Load detailed information
    this.loadCodeDetails(nrmCode)
  }

  assignSelectedCode() {
    if (!this.selectedCode) return

    const data = {
      element_id: this.elementIdValue,
      nrm_code: this.selectedCode,
      confidence: "manual"
    }

    fetch(`/nrm_lookup/assign_code`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("[name='csrf-token']").content
      },
      body: JSON.stringify(data)
    })
    .then(response => response.json())
    .then(result => {
      if (result.success) {
        this.close()
        location.reload() // Refresh to show assigned code
      } else {
        alert("Failed to assign NRM code: " + result.message)
      }
    })
    .catch(error => {
      console.error("Assignment failed:", error)
      alert("Failed to assign NRM code")
    })
  }

  async loadAISuggestions() {
    try {
      const response = await fetch(`/nrm_lookup/suggest?element_id=${this.elementIdValue}`)
      const data = await response.json()
      
      this.renderSuggestions(data.suggestions)
    } catch (error) {
      console.error("Failed to load AI suggestions:", error)
      this.suggestionsContainerTarget.innerHTML = '<div class="text-center py-8 text-red-600">Failed to load suggestions</div>'
    }
  }

  async loadPopularCodes() {
    try {
      const response = await fetch(`/nrm_lookup/search?popular=true`)
      const data = await response.json()
      
      this.renderPopularCodes(data.popular_codes)
    } catch (error) {
      console.error("Failed to load popular codes:", error)
    }
  }

  async loadCategories() {
    try {
      const response = await fetch(`/nrm_lookup/browse`)
      const data = await response.json()
      
      this.renderCategories(data.categories)
    } catch (error) {
      console.error("Failed to load categories:", error)
    }
  }

  async loadCodeDetails(nrmCode) {
    try {
      const response = await fetch(`/nrm_lookup/code_details?nrm_code=${nrmCode}`)
      const data = await response.json()
      
      // Update selected code info with more details
      this.selectedCodeInfoTarget.textContent = `Selected: ${data.item.code} - ${data.item.title} (${data.item.unit})`
    } catch (error) {
      console.error("Failed to load code details:", error)
    }
  }

  renderSuggestions(suggestions) {
    if (suggestions.length === 0) {
      this.suggestionsContainerTarget.innerHTML = '<div class="text-center py-8 text-gray-500">No AI suggestions available</div>'
      return
    }

    const html = suggestions.map(item => this.renderNrmItemCard(item)).join('')
    this.suggestionsContainerTarget.innerHTML = html
  }

  renderSearchResults(results) {
    if (results.length === 0) {
      this.searchResultsContainerTarget.innerHTML = '<div class="text-center py-4 text-gray-500">No results found</div>'
      return
    }

    const html = results.map(item => this.renderNrmItemCard(item)).join('')
    this.searchResultsContainerTarget.innerHTML = html
  }

  renderPopularCodes(codes) {
    if (codes.length === 0) return

    const html = codes.map(item => this.renderNrmItemCard(item)).join('')
    this.popularContainerTarget.innerHTML = html
  }

  renderCategories(categories) {
    const html = categories.map(cat => `
      <button type="button" 
              class="text-left px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 rounded-md w-full"
              data-action="click->nrm-lookup#selectCategory"
              data-category="${cat.code}">
        ${cat.name}
      </button>
    `).join('')
    
    this.categoriesContainerTarget.innerHTML = html
  }

  renderNrmItemCard(item) {
    const confidenceBadge = item.confidence ? 
      `<span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
        ${Math.round(item.confidence * 100)}% match
      </span>` : ''

    const reasoning = item.reasoning ? 
      `<div class="mt-2 p-2 bg-blue-50 rounded text-xs text-blue-800">
        <strong>AI Reasoning:</strong> ${item.reasoning}
      </div>` : ''

    return `
      <div class="border border-gray-200 rounded-lg p-4 hover:border-blue-300 hover:bg-blue-50 cursor-pointer transition-colors"
           data-nrm-code="${item.code}"
           data-action="click->nrm-lookup#selectCode">
        <div class="flex items-start justify-between">
          <div class="flex-1 min-w-0">
            <div class="flex items-center space-x-2 mb-2">
              <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                ${item.code}
              </span>
              ${confidenceBadge}
            </div>
            <h4 class="text-sm font-medium text-gray-900 mb-1">${item.title}</h4>
            <p class="text-xs text-gray-600 mb-2">${item.category} › ${item.subcategory}</p>
            ${item.description ? `<p class="text-xs text-gray-500 line-clamp-2">${item.description}</p>` : ''}
            ${reasoning}
          </div>
          <div class="flex-shrink-0 ml-4">
            <span class="text-xs text-gray-500">Unit: ${item.unit}</span>
          </div>
        </div>
      </div>
    `
  }
}
```

## Technical Notes
- AI-powered NRM suggestions provide intelligent defaults
- Hierarchical browsing enables systematic code discovery  
- Search functionality includes fuzzy matching and relevance scoring
- Real-time interface updates provide immediate feedback
- Audit trail tracks all NRM code assignments for compliance

## Definition of Done
- [ ] Search interface returns relevant NRM codes
- [ ] AI suggestions work with extracted element data
- [ ] Category browsing enables systematic exploration
- [ ] Code assignment updates element records correctly
- [ ] Mobile responsive interface works on all devices
- [ ] Performance is acceptable with large NRM database
- [ ] Code review completed