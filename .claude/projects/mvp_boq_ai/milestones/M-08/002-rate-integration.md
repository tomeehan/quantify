# M-08: Rate Application - Ticket 002: Rate Integration System

## Overview
Implement the rate integration system that connects NRM items with actual cost data, handles rate lookups, and manages supplier integrations for real-time pricing.

## Acceptance Criteria
- [ ] NRM items can be associated with multiple rates from different suppliers
- [ ] Rate lookup service can find best rates based on criteria (location, supplier, date)
- [ ] Supplier integration framework for importing rate data
- [ ] Rate versioning and effective date management
- [ ] Background jobs for rate updates and notifications

## Technical Implementation

### 1. Rate Association Service

```ruby
# app/services/rate_association_service.rb
class RateAssociationService
  def initialize(nrm_item)
    @nrm_item = nrm_item
  end

  def find_applicable_rates(criteria = {})
    location = criteria[:location]
    effective_date = criteria[:effective_date] || Date.current
    supplier_preference = criteria[:supplier_preference]

    rates = Rate.joins(:nrm_items)
                .where(nrm_items: { id: @nrm_item.id })
                .where('effective_from <= ? AND (effective_to IS NULL OR effective_to >= ?)', 
                       effective_date, effective_date)

    rates = rates.where(supplier: supplier_preference) if supplier_preference
    rates = apply_location_filter(rates, location) if location

    rates.order(:unit_rate)
  end

  def get_best_rate(criteria = {})
    find_applicable_rates(criteria).first
  end

  private

  def apply_location_filter(rates, location)
    # Apply regional pricing logic
    rates.where(
      'location_data IS NULL OR location_data @> ?',
      { regions: [location] }.to_json
    )
  end
end
```

### 2. Supplier Integration Framework

```ruby
# app/services/supplier_integrations/base_integration.rb
module SupplierIntegrations
  class BaseIntegration
    attr_reader :supplier, :account

    def initialize(supplier, account)
      @supplier = supplier
      @account = account
    end

    def sync_rates
      raise NotImplementedError, "Subclasses must implement sync_rates"
    end

    def validate_connection
      raise NotImplementedError, "Subclasses must implement validate_connection"
    end

    protected

    def create_or_update_rate(rate_data)
      Rate.find_or_initialize_by(
        account: account,
        supplier: supplier,
        nrm_code: rate_data[:nrm_code]
      ).tap do |rate|
        rate.assign_attributes(
          unit_rate: rate_data[:unit_rate],
          currency: rate_data[:currency],
          effective_from: rate_data[:effective_from],
          effective_to: rate_data[:effective_to],
          location_data: rate_data[:location_data],
          supplier_reference: rate_data[:supplier_reference]
        )
        rate.save!
      end
    end
  end
end

# app/services/supplier_integrations/csv_integration.rb
module SupplierIntegrations
  class CsvIntegration < BaseIntegration
    def sync_rates(file_path)
      CSV.foreach(file_path, headers: true) do |row|
        rate_data = {
          nrm_code: row['nrm_code'],
          unit_rate: BigDecimal(row['unit_rate']),
          currency: row['currency'] || 'GBP',
          effective_from: Date.parse(row['effective_from']),
          effective_to: row['effective_to'].present? ? Date.parse(row['effective_to']) : nil,
          location_data: parse_location_data(row['location']),
          supplier_reference: row['supplier_reference']
        }
        
        create_or_update_rate(rate_data)
      end
    end

    def validate_connection
      true # CSV doesn't require connection validation
    end

    private

    def parse_location_data(location_string)
      return nil if location_string.blank?
      { regions: location_string.split(',').map(&:strip) }
    end
  end
end
```

### 3. Rate Lookup Controller

```ruby
# app/controllers/accounts/rate_lookups_controller.rb
class Accounts::RateLookupsController < Accounts::BaseController
  before_action :authenticate_user!

  def search
    @nrm_item = current_account.nrm_items.find(params[:nrm_item_id])
    @criteria = rate_lookup_params
    
    service = RateAssociationService.new(@nrm_item)
    @rates = service.find_applicable_rates(@criteria)
    @best_rate = service.get_best_rate(@criteria)

    respond_to do |format|
      format.json { render json: rate_lookup_response }
      format.turbo_stream
    end
  end

  def apply_rate
    @element = current_account.elements.find(params[:element_id])
    @rate = current_account.rates.find(params[:rate_id])
    
    authorize @element
    
    @element.update!(
      applied_rate: @rate,
      unit_rate_override: @rate.unit_rate,
      rate_source: 'supplier_lookup',
      rate_applied_at: Time.current
    )

    redirect_to account_project_path(@element.project), 
                notice: "Rate applied successfully"
  end

  private

  def rate_lookup_params
    params.permit(:location, :supplier_preference, :effective_date)
  end

  def rate_lookup_response
    {
      rates: @rates.map do |rate|
        {
          id: rate.id,
          supplier_name: rate.supplier.name,
          unit_rate: rate.unit_rate,
          currency: rate.currency,
          effective_from: rate.effective_from,
          effective_to: rate.effective_to,
          location: rate.location_data
        }
      end,
      best_rate: @best_rate&.id,
      total_found: @rates.count
    }
  end
end
```

### 4. Background Jobs for Rate Updates

```ruby
# app/jobs/supplier_rate_sync_job.rb
class SupplierRateSyncJob < ApplicationJob
  queue_as :default

  def perform(supplier_id, integration_type = 'csv')
    supplier = Supplier.find(supplier_id)
    
    integration_class = "SupplierIntegrations::#{integration_type.classify}Integration".constantize
    integration = integration_class.new(supplier, supplier.account)
    
    if integration.validate_connection
      integration.sync_rates
      
      # Notify affected elements of rate changes
      NotifyRateChangesJob.perform_later(supplier)
    else
      Rails.logger.error "Failed to connect to supplier #{supplier.name}"
    end
  rescue StandardError => e
    Rails.logger.error "Rate sync failed for supplier #{supplier_id}: #{e.message}"
    raise e
  end
end

# app/jobs/notify_rate_changes_job.rb
class NotifyRateChangesJob < ApplicationJob
  queue_as :default

  def perform(supplier)
    affected_elements = Element.joins(:applied_rate)
                              .where(rates: { supplier: supplier })
                              .includes(:project, :account)

    affected_elements.group_by(&:account).each do |account, elements|
      elements.group_by(&:project).each do |project, project_elements|
        RateChangeNotificationService.new(project, project_elements).notify
      end
    end
  end
end
```

### 5. Rate Lookup Views

```erb
<!-- app/views/accounts/rate_lookups/search.turbo_stream.erb -->
<%= turbo_stream.update "rate_lookup_results" do %>
  <div class="bg-white rounded-lg shadow-sm border">
    <div class="px-6 py-4 border-b">
      <h3 class="text-lg font-medium">Available Rates for <%= @nrm_item.description %></h3>
      <p class="text-sm text-gray-600 mt-1">Found <%= @rates.count %> rates</p>
    </div>
    
    <div class="divide-y">
      <% @rates.each do |rate| %>
        <div class="px-6 py-4 flex items-center justify-between <%= 'bg-green-50 border-green-200' if rate.id == @best_rate&.id %>">
          <div class="flex-1">
            <div class="flex items-center space-x-4">
              <div>
                <p class="font-medium"><%= rate.supplier.name %></p>
                <p class="text-sm text-gray-600">
                  Valid: <%= rate.effective_from.strftime('%d/%m/%Y') %>
                  <% if rate.effective_to %>
                    - <%= rate.effective_to.strftime('%d/%m/%Y') %>
                  <% else %>
                    - Ongoing
                  <% end %>
                </p>
              </div>
              <div class="text-right">
                <p class="text-lg font-semibold">£<%= number_with_precision(rate.unit_rate, precision: 2) %></p>
                <p class="text-sm text-gray-600">per <%= @nrm_item.unit %></p>
              </div>
            </div>
          </div>
          
          <div class="ml-4">
            <%= link_to "Apply Rate", 
                account_rate_lookup_apply_path(
                  element_id: params[:element_id], 
                  rate_id: rate.id
                ),
                method: :patch,
                class: "inline-flex items-center px-3 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700",
                data: { confirm: "Apply this rate to the element?" } %>
          </div>
        </div>
      <% end %>
    </div>
  </div>
<% end %>
```

### 6. Stimulus Controller for Rate Lookup

```javascript
// app/javascript/controllers/rate_lookup_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "results", "nrmItem", "element"]
  static values = { 
    searchUrl: String,
    nrmItemId: Number,
    elementId: Number
  }

  connect() {
    this.performInitialSearch()
  }

  search(event) {
    event.preventDefault()
    
    const formData = new FormData(this.formTarget)
    formData.append('nrm_item_id', this.nrmItemIdValue)
    formData.append('element_id', this.elementIdValue)
    
    fetch(this.searchUrlValue, {
      method: 'POST',
      body: formData,
      headers: {
        'Accept': 'text/vnd.turbo-stream.html',
        'X-CSRF-Token': this.getCSRFToken()
      }
    })
    .then(response => response.text())
    .then(html => {
      Turbo.renderStreamMessage(html)
    })
  }

  performInitialSearch() {
    if (this.hasFormTarget) {
      this.search(new Event('submit'))
    }
  }

  getCSRFToken() {
    return document.querySelector('meta[name="csrf-token"]')?.getAttribute('content')
  }
}
```

## Testing Requirements

```ruby
# test/services/rate_association_service_test.rb
require 'test_helper'

class RateAssociationServiceTest < ActiveSupport::TestCase
  def setup
    @account = accounts(:company)
    @nrm_item = nrm_items(:excavation)
    @service = RateAssociationService.new(@nrm_item)
  end

  test "finds applicable rates for nrm item" do
    rates = @service.find_applicable_rates
    assert_includes rates, rates(:current_rate)
    refute_includes rates, rates(:expired_rate)
  end

  test "applies location filter when specified" do
    rates = @service.find_applicable_rates(location: 'London')
    assert rates.all? { |rate| rate.location_data.nil? || rate.location_data['regions'].include?('London') }
  end

  test "returns best rate as lowest unit rate" do
    best_rate = @service.get_best_rate
    assert_equal rates(:cheapest_rate), best_rate
  end
end

# test/jobs/supplier_rate_sync_job_test.rb
require 'test_helper'

class SupplierRateSyncJobTest < ActiveJob::TestCase
  test "syncs rates for supplier" do
    supplier = suppliers(:main_supplier)
    
    assert_difference 'Rate.count', 5 do
      SupplierRateSyncJob.perform_now(supplier.id, 'csv')
    end
  end

  test "handles sync failures gracefully" do
    supplier = suppliers(:invalid_supplier)
    
    assert_raises StandardError do
      SupplierRateSyncJob.perform_now(supplier.id, 'invalid')
    end
  end
end
```

## Routes

```ruby
# config/routes/accounts.rb
resources :rate_lookups, only: [] do
  collection do
    post :search
  end
  member do
    patch :apply_rate
  end
end

resources :suppliers do
  member do
    post :sync_rates
  end
end
```

## Database Migrations

```ruby
# Add supplier integrations
class AddSupplierIntegrationToSuppliers < ActiveRecord::Migration[8.0]
  def change
    add_column :suppliers, :integration_type, :string, default: 'manual'
    add_column :suppliers, :integration_config, :jsonb, default: {}
    add_column :suppliers, :last_sync_at, :timestamp
    add_column :suppliers, :sync_status, :string, default: 'pending'
    
    add_index :suppliers, :integration_type
    add_index :suppliers, :last_sync_at
  end
end

# Add rate source tracking to elements
class AddRateSourceToElements < ActiveRecord::Migration[8.0]
  def change
    add_column :elements, :rate_source, :string
    add_column :elements, :rate_applied_at, :timestamp
    add_reference :elements, :applied_rate, foreign_key: { to_table: :rates }
    
    add_index :elements, :rate_source
    add_index :elements, :rate_applied_at
  end
end
```