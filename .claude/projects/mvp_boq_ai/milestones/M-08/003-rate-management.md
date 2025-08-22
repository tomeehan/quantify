# M-08: Rate Application - Ticket 003: Rate Management Interface

## Overview
Implement comprehensive rate management interface allowing users to view, edit, approve, and manage rates across suppliers, with bulk operations and rate comparison tools.

## Acceptance Criteria
- [ ] Rate management dashboard with filtering and search
- [ ] Bulk rate operations (import, export, update, approve)
- [ ] Rate comparison tools showing price variations
- [ ] Rate approval workflow for sensitive changes
- [ ] Rate history and audit trail
- [ ] Rate alerts and notifications for significant changes

## Technical Implementation

### 1. Rate Management Controller

```ruby
# app/controllers/accounts/rates_controller.rb
class Accounts::RatesController < Accounts::BaseController
  before_action :authenticate_user!
  before_action :set_rate, only: [:show, :edit, :update, :destroy, :approve, :reject]
  before_action :set_filter_params, only: [:index]

  def index
    @rates = current_account.rates.includes(:supplier, :nrm_items)
    @rates = apply_filters(@rates)
    @rates = @rates.page(params[:page])
    
    @suppliers = current_account.suppliers.order(:name)
    @nrm_categories = current_account.nrm_items.distinct.pluck(:category).compact.sort
    
    respond_to do |format|
      format.html
      format.json { render json: rates_json_response }
      format.csv { send_data RateExportService.new(@rates).to_csv, filename: "rates_#{Date.current}.csv" }
    end
  end

  def show
    @rate_history = @rate.versions.includes(:actor).order(created_at: :desc)
    @affected_elements = current_account.elements.where(applied_rate: @rate)
    @alternative_rates = find_alternative_rates(@rate)
  end

  def new
    @rate = current_account.rates.build
    @suppliers = current_account.suppliers.order(:name)
    @nrm_items = current_account.nrm_items.order(:code)
  end

  def create
    @rate = current_account.rates.build(rate_params)
    authorize @rate

    if @rate.save
      log_rate_creation
      redirect_to account_rate_path(@rate), notice: 'Rate created successfully'
    else
      @suppliers = current_account.suppliers.order(:name)
      @nrm_items = current_account.nrm_items.order(:code)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @rate
    @suppliers = current_account.suppliers.order(:name)
    @nrm_items = current_account.nrm_items.order(:code)
  end

  def update
    authorize @rate
    old_unit_rate = @rate.unit_rate

    if @rate.update(rate_params)
      handle_rate_change(old_unit_rate) if rate_change_significant?(old_unit_rate)
      redirect_to account_rate_path(@rate), notice: 'Rate updated successfully'
    else
      @suppliers = current_account.suppliers.order(:name)
      @nrm_items = current_account.nrm_items.order(:code)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @rate
    
    if @rate.can_be_deleted?
      @rate.destroy
      redirect_to account_rates_path, notice: 'Rate deleted successfully'
    else
      redirect_to account_rate_path(@rate), 
                  alert: 'Cannot delete rate that is being used in projects'
    end
  end

  def bulk_operations
    case params[:operation]
    when 'approve'
      bulk_approve
    when 'reject'
      bulk_reject
    when 'export'
      bulk_export
    when 'update'
      bulk_update
    else
      redirect_to account_rates_path, alert: 'Invalid operation'
    end
  end

  def compare
    @rates = current_account.rates.where(id: params[:rate_ids])
    @comparison = RateComparisonService.new(@rates).generate_comparison
    
    respond_to do |format|
      format.html
      format.json { render json: @comparison }
    end
  end

  def approve
    authorize @rate, :approve?
    
    @rate.update!(
      status: 'approved',
      approved_by: current_user,
      approved_at: Time.current
    )
    
    # Notify affected users
    RateApprovalNotificationJob.perform_later(@rate)
    
    redirect_to account_rate_path(@rate), notice: 'Rate approved successfully'
  end

  def reject
    authorize @rate, :approve?
    
    @rate.update!(
      status: 'rejected',
      approved_by: current_user,
      approved_at: Time.current,
      rejection_reason: params[:rejection_reason]
    )
    
    redirect_to account_rate_path(@rate), notice: 'Rate rejected'
  end

  def import
    if params[:file].present?
      ImportRatesJob.perform_later(params[:file], current_account, current_user)
      redirect_to account_rates_path, notice: 'Rate import started. You will be notified when complete.'
    else
      redirect_to account_rates_path, alert: 'Please select a file to import'
    end
  end

  private

  def set_rate
    @rate = current_account.rates.find(params[:id])
  end

  def set_filter_params
    @filter_params = params.permit(:supplier_id, :category, :status, :effective_from, :effective_to, :search)
  end

  def apply_filters(rates)
    rates = rates.where(supplier_id: @filter_params[:supplier_id]) if @filter_params[:supplier_id].present?
    rates = rates.joins(:nrm_items).where(nrm_items: { category: @filter_params[:category] }) if @filter_params[:category].present?
    rates = rates.where(status: @filter_params[:status]) if @filter_params[:status].present?
    rates = rates.where('effective_from >= ?', @filter_params[:effective_from]) if @filter_params[:effective_from].present?
    rates = rates.where('effective_to <= ? OR effective_to IS NULL', @filter_params[:effective_to]) if @filter_params[:effective_to].present?
    
    if @filter_params[:search].present?
      search_term = "%#{@filter_params[:search]}%"
      rates = rates.joins(:nrm_items, :supplier)
                   .where('nrm_items.description ILIKE ? OR nrm_items.code ILIKE ? OR suppliers.name ILIKE ?', 
                          search_term, search_term, search_term)
    end
    
    rates
  end

  def rate_params
    params.require(:rate).permit(:supplier_id, :unit_rate, :currency, :effective_from, :effective_to, 
                                 :location_data, :supplier_reference, :notes, nrm_item_ids: [])
  end

  def find_alternative_rates(rate)
    current_account.rates
                   .joins(:nrm_items)
                   .where(nrm_items: { id: rate.nrm_item_ids })
                   .where.not(id: rate.id)
                   .where('effective_from <= ? AND (effective_to IS NULL OR effective_to >= ?)', 
                          Date.current, Date.current)
                   .includes(:supplier)
                   .order(:unit_rate)
  end

  def log_rate_creation
    Rails.logger.info "Rate created: #{@rate.id} by user #{current_user.id} for account #{current_account.id}"
  end

  def handle_rate_change(old_unit_rate)
    if rate_change_requires_approval?
      @rate.update!(status: 'pending_approval')
      RateChangeApprovalJob.perform_later(@rate, old_unit_rate, current_user)
    end
    
    # Notify affected projects
    NotifyRateChangesJob.perform_later(@rate.supplier)
  end

  def rate_change_significant?(old_unit_rate)
    return false if old_unit_rate.nil?
    
    percentage_change = ((@rate.unit_rate - old_unit_rate) / old_unit_rate).abs
    percentage_change > 0.1 # 10% threshold
  end

  def rate_change_requires_approval?
    current_account.settings.rate_approval_required? && 
    !current_user.can_approve_rates?
  end

  def bulk_approve
    rate_ids = params[:rate_ids] || []
    rates = current_account.rates.where(id: rate_ids)
    
    authorize_collection(rates, :approve?)
    
    rates.update_all(
      status: 'approved',
      approved_by_id: current_user.id,
      approved_at: Time.current
    )
    
    redirect_to account_rates_path, notice: "#{rates.count} rates approved"
  end

  def bulk_reject
    rate_ids = params[:rate_ids] || []
    rates = current_account.rates.where(id: rate_ids)
    
    authorize_collection(rates, :approve?)
    
    rates.update_all(
      status: 'rejected',
      approved_by_id: current_user.id,
      approved_at: Time.current
    )
    
    redirect_to account_rates_path, notice: "#{rates.count} rates rejected"
  end

  def bulk_export
    rate_ids = params[:rate_ids] || []
    rates = current_account.rates.where(id: rate_ids)
    
    csv_data = RateExportService.new(rates).to_csv
    send_data csv_data, filename: "selected_rates_#{Date.current}.csv", type: 'text/csv'
  end

  def bulk_update
    rate_ids = params[:rate_ids] || []
    update_params = params[:bulk_update] || {}
    
    rates = current_account.rates.where(id: rate_ids)
    authorize_collection(rates, :update?)
    
    BulkRateUpdateJob.perform_later(rate_ids, update_params, current_user)
    redirect_to account_rates_path, notice: "Bulk update started for #{rates.count} rates"
  end

  def authorize_collection(rates, action)
    rates.each { |rate| authorize rate, action }
  end

  def rates_json_response
    {
      rates: @rates.map do |rate|
        {
          id: rate.id,
          supplier_name: rate.supplier.name,
          nrm_codes: rate.nrm_items.pluck(:code),
          unit_rate: rate.unit_rate,
          currency: rate.currency,
          status: rate.status,
          effective_from: rate.effective_from,
          effective_to: rate.effective_to
        }
      end,
      pagination: {
        current_page: @rates.current_page,
        total_pages: @rates.total_pages,
        total_count: @rates.total_count
      }
    }
  end
end
```

### 2. Rate Comparison Service

```ruby
# app/services/rate_comparison_service.rb
class RateComparisonService
  def initialize(rates)
    @rates = rates.includes(:supplier, :nrm_items)
  end

  def generate_comparison
    {
      summary: generate_summary,
      detailed_comparison: generate_detailed_comparison,
      price_analysis: generate_price_analysis,
      recommendations: generate_recommendations
    }
  end

  private

  def generate_summary
    {
      total_rates: @rates.count,
      suppliers: @rates.map(&:supplier).uniq.count,
      nrm_items: @rates.flat_map(&:nrm_items).uniq.count,
      price_range: {
        min: @rates.minimum(:unit_rate),
        max: @rates.maximum(:unit_rate),
        average: @rates.average(:unit_rate)&.round(2)
      },
      currencies: @rates.distinct.pluck(:currency)
    }
  end

  def generate_detailed_comparison
    @rates.group_by { |rate| rate.nrm_items.first&.code }.map do |nrm_code, rates|
      {
        nrm_code: nrm_code,
        description: rates.first&.nrm_items&.first&.description,
        rates: rates.map do |rate|
          {
            id: rate.id,
            supplier: rate.supplier.name,
            unit_rate: rate.unit_rate,
            currency: rate.currency,
            effective_from: rate.effective_from,
            effective_to: rate.effective_to,
            status: rate.status
          }
        end.sort_by { |r| r[:unit_rate] }
      }
    end
  end

  def generate_price_analysis
    rates_by_supplier = @rates.group_by(&:supplier)
    
    {
      supplier_averages: rates_by_supplier.map do |supplier, rates|
        {
          supplier: supplier.name,
          average_rate: rates.sum(&:unit_rate) / rates.count,
          rate_count: rates.count,
          competitiveness: calculate_competitiveness(rates)
        }
      end.sort_by { |s| s[:average_rate] },
      
      price_distribution: calculate_price_distribution,
      outliers: identify_outliers
    }
  end

  def generate_recommendations
    recommendations = []
    
    # Identify best value suppliers
    best_rates = @rates.group_by { |r| r.nrm_items.first&.code }
                       .map { |_, rates| rates.min_by(&:unit_rate) }
    
    best_suppliers = best_rates.group_by(&:supplier)
                               .map { |supplier, rates| [supplier, rates.count] }
                               .sort_by(&:last)
                               .reverse
    
    if best_suppliers.any?
      recommendations << {
        type: 'supplier_preference',
        message: "#{best_suppliers.first[0].name} offers the best rates for #{best_suppliers.first[1]} items",
        data: { supplier_id: best_suppliers.first[0].id }
      }
    end
    
    # Identify price inconsistencies
    price_gaps = identify_significant_price_gaps
    if price_gaps.any?
      recommendations << {
        type: 'price_negotiation',
        message: "Significant price differences found for #{price_gaps.count} items - consider negotiation",
        data: { nrm_codes: price_gaps }
      }
    end
    
    recommendations
  end

  def calculate_competitiveness(rates)
    return 0 if rates.empty?
    
    all_rates_for_items = @rates.select do |rate|
      rates.any? { |r| (r.nrm_item_ids & rate.nrm_item_ids).any? }
    end
    
    return 0 if all_rates_for_items.empty?
    
    avg_market_rate = all_rates_for_items.sum(&:unit_rate) / all_rates_for_items.count
    avg_supplier_rate = rates.sum(&:unit_rate) / rates.count
    
    # Lower is better, so inverse the calculation
    ((avg_market_rate - avg_supplier_rate) / avg_market_rate * 100).round(1)
  end

  def calculate_price_distribution
    rates = @rates.map(&:unit_rate).sort
    
    {
      quartiles: {
        q1: rates[rates.length / 4],
        q2: rates[rates.length / 2],
        q3: rates[rates.length * 3 / 4]
      },
      standard_deviation: calculate_standard_deviation(rates),
      range: rates.last - rates.first
    }
  end

  def identify_outliers
    rates = @rates.map(&:unit_rate)
    mean = rates.sum / rates.length
    std_dev = calculate_standard_deviation(rates)
    
    @rates.select do |rate|
      (rate.unit_rate - mean).abs > (2 * std_dev)
    end.map do |rate|
      {
        id: rate.id,
        supplier: rate.supplier.name,
        unit_rate: rate.unit_rate,
        deviation: ((rate.unit_rate - mean) / std_dev).round(2)
      }
    end
  end

  def identify_significant_price_gaps
    @rates.group_by { |r| r.nrm_items.first&.code }
          .select { |_, rates| rates.count > 1 }
          .select do |_, rates|
            min_rate = rates.min_by(&:unit_rate).unit_rate
            max_rate = rates.max_by(&:unit_rate).unit_rate
            (max_rate - min_rate) / min_rate > 0.3 # 30% difference
          end
          .keys
  end

  def calculate_standard_deviation(values)
    return 0 if values.length <= 1
    
    mean = values.sum / values.length
    variance = values.sum { |v| (v - mean) ** 2 } / values.length
    Math.sqrt(variance)
  end
end
```

### 3. Rate Management Dashboard

```erb
<!-- app/views/accounts/rates/index.html.erb -->
<div class="space-y-6" data-controller="rate-management" 
     data-rate-management-bulk-operations-url-value="<%= bulk_operations_account_rates_path %>">
  
  <!-- Header and Actions -->
  <div class="flex items-center justify-between">
    <div>
      <h1 class="text-2xl font-bold text-gray-900">Rate Management</h1>
      <p class="mt-1 text-sm text-gray-600">
        Manage rates across suppliers and track pricing changes
      </p>
    </div>
    
    <div class="flex items-center space-x-3">
      <%= link_to "Import Rates", 
          new_account_rate_path, 
          class: "inline-flex items-center px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50" %>
      
      <%= button_to "Export Selected", 
          bulk_operations_account_rates_path, 
          method: :post,
          params: { operation: 'export' },
          form: { data: { action: 'rate-management#bulkExport' } },
          class: "inline-flex items-center px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50" %>
      
      <%= link_to "Add Rate", 
          new_account_rate_path, 
          class: "inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700" %>
    </div>
  </div>

  <!-- Filters -->
  <%= form_with url: account_rates_path, method: :get, local: true, class: "bg-white rounded-lg shadow-sm border p-6" do |form| %>
    <div class="grid grid-cols-1 md:grid-cols-5 gap-4">
      <div>
        <%= form.select :supplier_id, 
            options_from_collection_for_select(@suppliers, :id, :name, params[:supplier_id]),
            { prompt: 'All Suppliers' },
            { class: 'block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500' } %>
      </div>
      
      <div>
        <%= form.select :category,
            options_for_select(@nrm_categories.map { |c| [c.humanize, c] }, params[:category]),
            { prompt: 'All Categories' },
            { class: 'block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500' } %>
      </div>
      
      <div>
        <%= form.select :status,
            options_for_select([
              ['Approved', 'approved'],
              ['Pending', 'pending'],
              ['Rejected', 'rejected']
            ], params[:status]),
            { prompt: 'All Statuses' },
            { class: 'block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500' } %>
      </div>
      
      <div>
        <%= form.text_field :search,
            placeholder: 'Search rates...',
            value: params[:search],
            class: 'block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500' %>
      </div>
      
      <div>
        <%= form.submit "Filter", 
            class: "w-full inline-flex justify-center items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700" %>
      </div>
    </div>
  <% end %>

  <!-- Bulk Operations Bar -->
  <div id="bulk-operations-bar" class="hidden bg-blue-50 border border-blue-200 rounded-lg p-4">
    <div class="flex items-center justify-between">
      <div class="flex items-center space-x-4">
        <span class="text-sm font-medium text-blue-900">
          <span data-rate-management-target="selectedCount">0</span> rates selected
        </span>
      </div>
      
      <div class="flex items-center space-x-2">
        <%= button_to "Approve Selected", 
            bulk_operations_account_rates_path,
            method: :post,
            params: { operation: 'approve' },
            form: { data: { action: 'rate-management#bulkApprove' } },
            class: "inline-flex items-center px-3 py-2 border border-transparent text-sm font-medium rounded-md text-green-700 bg-green-100 hover:bg-green-200" %>
        
        <%= button_to "Reject Selected", 
            bulk_operations_account_rates_path,
            method: :post,
            params: { operation: 'reject' },
            form: { data: { action: 'rate-management#bulkReject' } },
            class: "inline-flex items-center px-3 py-2 border border-transparent text-sm font-medium rounded-md text-red-700 bg-red-100 hover:bg-red-200" %>
        
        <button data-action="rate-management#clearSelection" 
                class="inline-flex items-center px-3 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50">
          Clear
        </button>
      </div>
    </div>
  </div>

  <!-- Rates Table -->
  <div class="bg-white rounded-lg shadow-sm border overflow-hidden">
    <table class="min-w-full divide-y divide-gray-200">
      <thead class="bg-gray-50">
        <tr>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
            <input type="checkbox" 
                   data-action="rate-management#toggleAll"
                   data-rate-management-target="selectAll"
                   class="rounded border-gray-300 text-blue-600 focus:ring-blue-500">
          </th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
            Supplier / NRM Code
          </th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
            Rate
          </th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
            Effective Period
          </th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
            Status
          </th>
          <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
            Actions
          </th>
        </tr>
      </thead>
      <tbody class="bg-white divide-y divide-gray-200">
        <% @rates.each do |rate| %>
          <tr class="hover:bg-gray-50">
            <td class="px-6 py-4 whitespace-nowrap">
              <input type="checkbox" 
                     value="<%= rate.id %>"
                     data-action="rate-management#toggleSelection"
                     data-rate-management-target="rateCheckbox"
                     class="rounded border-gray-300 text-blue-600 focus:ring-blue-500">
            </td>
            
            <td class="px-6 py-4 whitespace-nowrap">
              <div class="flex items-center">
                <div>
                  <div class="text-sm font-medium text-gray-900">
                    <%= rate.supplier.name %>
                  </div>
                  <div class="text-sm text-gray-500">
                    <%= rate.nrm_items.pluck(:code).join(', ') %>
                  </div>
                </div>
              </div>
            </td>
            
            <td class="px-6 py-4 whitespace-nowrap">
              <div class="text-sm text-gray-900">
                <%= rate.currency %> <%= number_with_precision(rate.unit_rate, precision: 2) %>
              </div>
              <div class="text-sm text-gray-500">
                per <%= rate.nrm_items.first&.unit %>
              </div>
            </td>
            
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
              <%= rate.effective_from.strftime('%d/%m/%Y') %>
              <% if rate.effective_to %>
                - <%= rate.effective_to.strftime('%d/%m/%Y') %>
              <% else %>
                - Ongoing
              <% end %>
            </td>
            
            <td class="px-6 py-4 whitespace-nowrap">
              <span class="inline-flex px-2 py-1 text-xs font-semibold rounded-full 
                         <%= rate.status == 'approved' ? 'bg-green-100 text-green-800' : 
                             rate.status == 'rejected' ? 'bg-red-100 text-red-800' : 
                             'bg-yellow-100 text-yellow-800' %>">
                <%= rate.status.humanize %>
              </span>
            </td>
            
            <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
              <div class="flex items-center justify-end space-x-2">
                <%= link_to "View", account_rate_path(rate), 
                    class: "text-blue-600 hover:text-blue-900" %>
                <%= link_to "Edit", edit_account_rate_path(rate), 
                    class: "text-gray-600 hover:text-gray-900" %>
              </div>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </div>

  <!-- Pagination -->
  <div class="flex items-center justify-between">
    <div class="text-sm text-gray-700">
      Showing <%= @rates.offset_value + 1 %> to <%= [@rates.offset_value + @rates.limit_value, @rates.total_count].min %> 
      of <%= @rates.total_count %> rates
    </div>
    
    <%= paginate @rates, theme: 'twitter_bootstrap_5' %>
  </div>
</div>
```

### 4. Stimulus Controller for Rate Management

```javascript
// app/javascript/controllers/rate_management_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["selectAll", "rateCheckbox", "selectedCount"]
  static values = { bulkOperationsUrl: String }

  connect() {
    this.updateBulkOperationsBar()
  }

  toggleAll(event) {
    const checked = event.target.checked
    this.rateCheckboxTargets.forEach(checkbox => {
      checkbox.checked = checked
    })
    this.updateBulkOperationsBar()
  }

  toggleSelection() {
    this.updateSelectAllState()
    this.updateBulkOperationsBar()
  }

  clearSelection() {
    this.selectAllTarget.checked = false
    this.rateCheckboxTargets.forEach(checkbox => {
      checkbox.checked = false
    })
    this.updateBulkOperationsBar()
  }

  bulkApprove(event) {
    event.preventDefault()
    this.performBulkOperation('approve')
  }

  bulkReject(event) {
    event.preventDefault()
    this.performBulkOperation('reject')
  }

  bulkExport(event) {
    event.preventDefault()
    this.performBulkOperation('export')
  }

  updateSelectAllState() {
    const checkedBoxes = this.rateCheckboxTargets.filter(cb => cb.checked)
    const allBoxes = this.rateCheckboxTargets
    
    if (checkedBoxes.length === 0) {
      this.selectAllTarget.indeterminate = false
      this.selectAllTarget.checked = false
    } else if (checkedBoxes.length === allBoxes.length) {
      this.selectAllTarget.indeterminate = false
      this.selectAllTarget.checked = true
    } else {
      this.selectAllTarget.indeterminate = true
      this.selectAllTarget.checked = false
    }
  }

  updateBulkOperationsBar() {
    const selectedRates = this.getSelectedRateIds()
    const bulkBar = document.getElementById('bulk-operations-bar')
    
    if (selectedRates.length > 0) {
      bulkBar.classList.remove('hidden')
      this.selectedCountTarget.textContent = selectedRates.length
    } else {
      bulkBar.classList.add('hidden')
    }
  }

  getSelectedRateIds() {
    return this.rateCheckboxTargets
      .filter(checkbox => checkbox.checked)
      .map(checkbox => checkbox.value)
  }

  performBulkOperation(operation) {
    const rateIds = this.getSelectedRateIds()
    
    if (rateIds.length === 0) {
      alert('Please select at least one rate')
      return
    }

    const formData = new FormData()
    formData.append('operation', operation)
    rateIds.forEach(id => formData.append('rate_ids[]', id))

    if (operation === 'export') {
      this.downloadFile(formData)
    } else {
      this.submitBulkOperation(formData)
    }
  }

  submitBulkOperation(formData) {
    fetch(this.bulkOperationsUrlValue, {
      method: 'POST',
      body: formData,
      headers: {
        'X-CSRF-Token': this.getCSRFToken()
      }
    })
    .then(response => {
      if (response.ok) {
        window.location.reload()
      } else {
        alert('Operation failed. Please try again.')
      }
    })
    .catch(error => {
      console.error('Error:', error)
      alert('Operation failed. Please try again.')
    })
  }

  downloadFile(formData) {
    const form = document.createElement('form')
    form.method = 'POST'
    form.action = this.bulkOperationsUrlValue
    
    for (let [key, value] of formData.entries()) {
      const input = document.createElement('input')
      input.type = 'hidden'
      input.name = key
      input.value = value
      form.appendChild(input)
    }
    
    const csrfInput = document.createElement('input')
    csrfInput.type = 'hidden'
    csrfInput.name = 'authenticity_token'
    csrfInput.value = this.getCSRFToken()
    form.appendChild(csrfInput)
    
    document.body.appendChild(form)
    form.submit()
    document.body.removeChild(form)
  }

  getCSRFToken() {
    return document.querySelector('meta[name="csrf-token"]')?.getAttribute('content')
  }
}
```

## Testing Requirements

```ruby
# test/controllers/accounts/rates_controller_test.rb
require 'test_helper'

class Accounts::RatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:company)
    @user = users(:accountant)
    @rate = rates(:approved_rate)
    sign_in_as @user
    switch_account @account
  end

  test "should get index" do
    get account_rates_path
    assert_response :success
    assert_includes response.body, @rate.supplier.name
  end

  test "should filter rates by supplier" do
    get account_rates_path, params: { supplier_id: @rate.supplier.id }
    assert_response :success
    assert_includes response.body, @rate.supplier.name
  end

  test "should handle bulk approve operation" do
    rates = [@rate, rates(:pending_rate)]
    
    post bulk_operations_account_rates_path, params: {
      operation: 'approve',
      rate_ids: rates.map(&:id)
    }
    
    assert_redirected_to account_rates_path
    assert rates.all? { |r| r.reload.approved? }
  end

  test "should export selected rates as CSV" do
    post bulk_operations_account_rates_path, params: {
      operation: 'export',
      rate_ids: [@rate.id]
    }
    
    assert_response :success
    assert_equal 'text/csv', response.content_type
  end
end

# test/services/rate_comparison_service_test.rb
require 'test_helper'

class RateComparisonServiceTest < ActiveSupport::TestCase
  def setup
    @rates = rates(:approved_rate, :pending_rate, :expensive_rate)
    @service = RateComparisonService.new(Rate.where(id: @rates.map(&:id)))
  end

  test "generates comprehensive comparison" do
    comparison = @service.generate_comparison
    
    assert_includes comparison.keys, :summary
    assert_includes comparison.keys, :detailed_comparison
    assert_includes comparison.keys, :price_analysis
    assert_includes comparison.keys, :recommendations
  end

  test "identifies price outliers" do
    comparison = @service.generate_comparison
    outliers = comparison[:price_analysis][:outliers]
    
    assert outliers.any? { |o| o[:id] == rates(:expensive_rate).id }
  end

  test "recommends best value suppliers" do
    comparison = @service.generate_comparison
    recommendations = comparison[:recommendations]
    
    supplier_rec = recommendations.find { |r| r[:type] == 'supplier_preference' }
    assert_not_nil supplier_rec
  end
end
```

## Routes

```ruby
# config/routes/accounts.rb
resources :rates do
  collection do
    post :bulk_operations
    post :import
    get :compare
  end
  
  member do
    patch :approve
    patch :reject
  end
end
```