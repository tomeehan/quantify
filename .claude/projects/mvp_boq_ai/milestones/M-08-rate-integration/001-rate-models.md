# Ticket 1: Rate Models and Integration

**Epic**: M8 Rate Application  
**Story Points**: 4  
**Dependencies**: M-07 (Quantity calculation)

## Description
Create comprehensive rate management system that integrates with external rate databases, applies regional pricing, handles multiple rate types (Labour, Plant, Material), and supports rate versioning and historical tracking.

## Acceptance Criteria
- [ ] Rate models with type categorization and regional scoping
- [ ] External rate database integration with sync capabilities
- [ ] Rate versioning and effective date management
- [ ] Automatic rate application based on NRM codes and regions
- [ ] Rate override capabilities with audit trails
- [ ] Background sync jobs for rate updates

## Code to be Written

### 1. Rate Model
```ruby
# app/models/rate.rb
class Rate < ApplicationRecord
  RATE_TYPES = %w[labour plant material overhead].freeze
  REGIONS = %w[london manchester birmingham glasgow edinburgh].freeze

  belongs_to :nrm_item, optional: true
  has_many :boq_lines, dependent: :nullify

  validates :code, presence: true
  validates :description, presence: true
  validates :rate_type, inclusion: { in: RATE_TYPES }
  validates :region, inclusion: { in: REGIONS }
  validates :unit, presence: true
  validates :rate_per_unit, presence: true, numericality: { greater_than: 0 }
  validates :effective_from, presence: true
  validates :data_source, presence: true

  scope :current, -> { where('effective_from <= ? AND (effective_to IS NULL OR effective_to > ?)', Date.current, Date.current) }
  scope :for_region, ->(region) { where(region: region) }
  scope :by_type, ->(type) { where(rate_type: type) }
  scope :for_nrm_code, ->(code) { joins(:nrm_item).where(nrm_items: { code: code }) }

  def self.find_applicable_rate(nrm_code, region, rate_type, date = Date.current)
    current.for_region(region)
           .by_type(rate_type)
           .for_nrm_code(nrm_code)
           .where('effective_from <= ?', date)
           .order(effective_from: :desc)
           .first
  end

  def current?
    effective_from <= Date.current && (effective_to.nil? || effective_to > Date.current)
  end

  def expired?
    effective_to.present? && effective_to <= Date.current
  end

  def rate_with_markup(markup_percentage = 0)
    base_rate = rate_per_unit
    markup_amount = base_rate * (markup_percentage / 100.0)
    base_rate + markup_amount
  end
end
```

### 2. Rate Sync Service
```ruby
# app/services/rate_sync_service.rb
class RateSyncService
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :region, :string
  attribute :rate_types, :array, default: Rate::RATE_TYPES
  attribute :force_update, :boolean, default: false

  def call
    @sync_results = {
      updated: 0,
      created: 0,
      errors: [],
      last_sync: Time.current
    }

    rate_types.each do |rate_type|
      sync_rate_type(rate_type)
    end

    log_sync_results
    @sync_results
  end

  private

  def sync_rate_type(rate_type)
    Rails.logger.info("Syncing #{rate_type} rates for #{region}")
    
    external_rates = fetch_external_rates(rate_type)
    
    external_rates.each do |external_rate|
      sync_individual_rate(external_rate, rate_type)
    end
  rescue => e
    error_msg = "Failed to sync #{rate_type} rates: #{e.message}"
    Rails.logger.error(error_msg)
    @sync_results[:errors] << error_msg
  end

  def fetch_external_rates(rate_type)
    client = ExternalRateClient.new(
      region: region,
      rate_type: rate_type,
      api_key: Rails.application.credentials.rate_db_api_key
    )
    
    client.fetch_current_rates
  end

  def sync_individual_rate(external_rate, rate_type)
    existing_rate = find_existing_rate(external_rate, rate_type)
    
    if existing_rate && !needs_update?(existing_rate, external_rate)
      return # No update needed
    end

    rate_attributes = build_rate_attributes(external_rate, rate_type)
    
    if existing_rate
      existing_rate.update!(rate_attributes)
      @sync_results[:updated] += 1
    else
      Rate.create!(rate_attributes)
      @sync_results[:created] += 1
    end
  end

  def find_existing_rate(external_rate, rate_type)
    Rate.current
        .for_region(region)
        .by_type(rate_type)
        .find_by(code: external_rate['code'])
  end

  def needs_update?(existing_rate, external_rate)
    return true if force_update
    
    # Check if rate has changed significantly (>1%)
    rate_difference = (external_rate['rate_per_unit'] - existing_rate.rate_per_unit).abs
    rate_change_percentage = (rate_difference / existing_rate.rate_per_unit) * 100
    
    rate_change_percentage > 1.0
  end

  def build_rate_attributes(external_rate, rate_type)
    {
      code: external_rate['code'],
      description: external_rate['description'],
      rate_type: rate_type,
      region: region,
      unit: external_rate['unit'],
      rate_per_unit: external_rate['rate_per_unit'],
      effective_from: Date.parse(external_rate['effective_from']),
      effective_to: external_rate['effective_to'] ? Date.parse(external_rate['effective_to']) : nil,
      data_source: 'external_api',
      external_id: external_rate['id'],
      sync_metadata: {
        synced_at: Time.current,
        api_version: external_rate['api_version'],
        source_updated_at: external_rate['updated_at']
      }
    }
  end

  def log_sync_results
    Rails.logger.info("Rate sync completed", @sync_results)
  end
end
```

### 3. External Rate Client
```ruby
# app/services/external_rate_client.rb
class ExternalRateClient
  include HTTParty
  
  base_uri Rails.application.credentials.rate_db_base_url || 'https://api.ratedb.example.com'
  
  attr_reader :region, :rate_type, :api_key

  def initialize(region:, rate_type:, api_key:)
    @region = region
    @rate_type = rate_type
    @api_key = api_key
  end

  def fetch_current_rates
    response = self.class.get("/rates", {
      query: {
        region: region,
        rate_type: rate_type,
        effective_date: Date.current.iso8601,
        format: 'json'
      },
      headers: {
        'Authorization' => "Bearer #{api_key}",
        'Content-Type' => 'application/json',
        'User-Agent' => 'BoQ-AI/1.0'
      },
      timeout: 30
    })

    handle_response(response)
  end

  def fetch_rate_by_code(code)
    response = self.class.get("/rates/#{code}", {
      query: {
        region: region,
        effective_date: Date.current.iso8601
      },
      headers: {
        'Authorization' => "Bearer #{api_key}",
        'Content-Type' => 'application/json'
      },
      timeout: 15
    })

    handle_response(response)
  end

  private

  def handle_response(response)
    case response.code
    when 200
      response.parsed_response['data'] || []
    when 401
      raise AuthenticationError, "Invalid API key for rate database"
    when 404
      raise NotFoundError, "No rates found for #{region}/#{rate_type}"
    when 429
      raise RateLimitError, "Rate limit exceeded for rate database API"
    when 500..599
      raise ServiceError, "Rate database service error: #{response.code}"
    else
      raise UnknownError, "Unexpected response: #{response.code}"
    end
  end
end

class RateClientError < StandardError; end
class AuthenticationError < RateClientError; end
class NotFoundError < RateClientError; end
class RateLimitError < RateClientError; end
class ServiceError < RateClientError; end
class UnknownError < RateClientError; end
```

### 4. Rate Application Service
```ruby
# app/services/rate_application_service.rb
class RateApplicationService
  attr_reader :quantity, :options

  def initialize(quantity, options = {})
    @quantity = quantity
    @options = options.with_indifferent_access
  end

  def apply_rates
    return [] unless quantity.assembly&.nrm_item

    applicable_rates = find_applicable_rates
    
    applicable_rates.map do |rate|
      create_or_update_boq_line(rate)
    end.compact
  end

  private

  def find_applicable_rates
    nrm_code = quantity.assembly.nrm_item.code
    region = quantity.element.project.region
    
    # Find all applicable rate types for this assembly
    rate_types = determine_required_rate_types
    
    rate_types.filter_map do |rate_type|
      Rate.find_applicable_rate(nrm_code, region, rate_type)
    end
  end

  def determine_required_rate_types
    # Default rate types based on assembly type
    base_types = %w[labour material]
    
    # Add plant if assembly requires equipment
    if quantity.assembly.inputs_schema.dig('properties', 'requires_plant')
      base_types << 'plant'
    end
    
    # Add overhead based on project settings
    if quantity.element.project.settings&.dig('include_overheads')
      base_types << 'overhead'
    end
    
    base_types
  end

  def create_or_update_boq_line(rate)
    boq_line = BoqLine.find_or_initialize_by(
      quantity: quantity,
      rate: rate
    )

    line_quantity = calculate_line_quantity(rate)
    line_total = line_quantity * rate.rate_per_unit

    boq_line.assign_attributes(
      description: build_line_description(rate),
      unit: rate.unit,
      quantity_amount: line_quantity,
      rate_per_unit: rate.rate_per_unit,
      total_amount: line_total,
      calculation_data: {
        base_quantity: quantity.calculated_amount,
        conversion_factor: calculate_conversion_factor(rate),
        rate_source: rate.data_source,
        calculated_at: Time.current
      }
    )

    if boq_line.save
      Rails.logger.info("BoQ line created/updated", {
        quantity_id: quantity.id,
        rate_id: rate.id,
        total: line_total
      })
      boq_line
    else
      Rails.logger.error("Failed to save BoQ line", {
        quantity_id: quantity.id,
        rate_id: rate.id,
        errors: boq_line.errors.full_messages
      })
      nil
    end
  end

  def calculate_line_quantity(rate)
    # Handle unit conversions if needed
    base_quantity = quantity.calculated_amount
    
    if quantity.unit == rate.unit
      base_quantity
    else
      # Apply unit conversion
      UnitConverter.convert(
        amount: base_quantity,
        from: quantity.unit,
        to: rate.unit
      )
    end
  end

  def calculate_conversion_factor(rate)
    return 1.0 if quantity.unit == rate.unit
    
    UnitConverter.conversion_factor(
      from: quantity.unit,
      to: rate.unit
    )
  end

  def build_line_description(rate)
    base_desc = "#{rate.description} - #{rate.rate_type.humanize}"
    
    if options[:include_element_reference]
      "#{quantity.element.name}: #{base_desc}"
    else
      base_desc
    end
  end
end
```

### 5. Rate Sync Job
```ruby
# app/jobs/rate_sync_job.rb
class RateSyncJob < ApplicationJob
  include JobErrorHandling
  
  queue_as :default
  
  retry_on RateClientError, wait: :exponentially_longer, attempts: 5
  discard_on AuthenticationError

  def perform(region = nil, rate_types = nil, force_update = false)
    regions_to_sync = region ? [region] : Rate::REGIONS
    types_to_sync = rate_types || Rate::RATE_TYPES
    
    results = {}
    
    regions_to_sync.each do |sync_region|
      Rails.logger.info("Starting rate sync for region: #{sync_region}")
      
      begin
        sync_result = RateSyncService.call(
          region: sync_region,
          rate_types: types_to_sync,
          force_update: force_update
        )
        
        results[sync_region] = sync_result
        
      rescue => e
        Rails.logger.error("Rate sync failed for #{sync_region}: #{e.message}")
        results[sync_region] = { error: e.message }
      end
    end
    
    # Broadcast completion notification
    broadcast_sync_completion(results)
    
    results
  end

  private

  def broadcast_sync_completion(results)
    total_updated = results.values.sum { |r| r[:updated] || 0 }
    total_created = results.values.sum { |r| r[:created] || 0 }
    total_errors = results.values.sum { |r| r[:errors]&.count || 0 }
    
    message = "Rate sync completed: #{total_created} created, #{total_updated} updated"
    message += ", #{total_errors} errors" if total_errors > 0
    
    # Broadcast to admin channel
    Turbo::StreamsChannel.broadcast_action_to(
      "admin_notifications",
      action: :append,
      target: "notifications",
      partial: "admin/notification",
      locals: { 
        type: total_errors > 0 ? :warning : :success,
        message: message,
        details: results
      }
    )
  end
end
```

## Technical Notes
- External API integration with robust error handling
- Rate versioning supports historical pricing analysis
- Automatic rate application reduces manual effort
- Unit conversion handles different measurement systems
- Background sync keeps rates current without blocking UI

## Definition of Done
- [ ] Rate models handle all required scenarios
- [ ] External API integration works reliably
- [ ] Rate application creates correct BoQ lines
- [ ] Sync jobs run without errors
- [ ] Unit conversions are accurate
- [ ] Error handling covers API failures
- [ ] Test coverage exceeds 90%
- [ ] Code review completed