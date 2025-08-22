# Ticket 2: Snapshot Comparison Interface

**Epic**: M11 Snapshot Management  
**Story Points**: 6  
**Dependencies**: 001-snapshot-models.md

## Description
Create a comprehensive snapshot comparison interface that allows users to compare different versions of their BoQ, identify changes in quantities and pricing, and understand the impact of project modifications over time.

## Acceptance Criteria
- [ ] Side-by-side snapshot comparison view
- [ ] Detailed change detection for quantities, rates, and totals
- [ ] Visual diff highlighting with color-coded changes
- [ ] Summary of changes with financial impact analysis
- [ ] Exportable comparison reports
- [ ] Timeline view showing snapshot evolution
- [ ] Rollback functionality to restore previous snapshot

## Code to be Written

### 1. Snapshot Comparison Service
```ruby
# app/services/snapshot_comparison_service.rb
class SnapshotComparisonService
  include ActiveModel::Model

  attr_reader :baseline_snapshot, :comparison_snapshot, :comparison_result

  def initialize(baseline_snapshot, comparison_snapshot)
    @baseline_snapshot = baseline_snapshot
    @comparison_snapshot = comparison_snapshot
    @comparison_result = {}
  end

  def generate_comparison
    @comparison_result = {
      metadata: generate_metadata,
      summary: generate_summary,
      line_changes: analyze_line_changes,
      quantity_changes: analyze_quantity_changes,
      rate_changes: analyze_rate_changes,
      financial_impact: calculate_financial_impact,
      element_changes: analyze_element_changes
    }
  end

  def export_comparison_report(format: :json)
    case format
    when :json
      comparison_result.to_json
    when :csv
      generate_csv_report
    when :pdf
      generate_pdf_report
    else
      raise ArgumentError, "Unsupported format: #{format}"
    end
  end

  private

  def generate_metadata
    {
      baseline: {
        id: baseline_snapshot.id,
        name: baseline_snapshot.name,
        created_at: baseline_snapshot.created_at,
        total_value: baseline_snapshot.total_value
      },
      comparison: {
        id: comparison_snapshot.id,
        name: comparison_snapshot.name,
        created_at: comparison_snapshot.created_at,
        total_value: comparison_snapshot.total_value
      },
      time_difference: comparison_snapshot.created_at - baseline_snapshot.created_at,
      comparison_generated_at: Time.current
    }
  end

  def generate_summary
    baseline_data = baseline_snapshot.snapshot_data
    comparison_data = comparison_snapshot.snapshot_data

    {
      total_value_change: comparison_data['total_value'] - baseline_data['total_value'],
      total_value_change_percentage: calculate_percentage_change(
        baseline_data['total_value'], 
        comparison_data['total_value']
      ),
      line_count_change: comparison_data['boq_lines'].size - baseline_data['boq_lines'].size,
      element_count_change: comparison_data['elements'].size - baseline_data['elements'].size,
      major_changes: count_major_changes,
      minor_changes: count_minor_changes
    }
  end

  def analyze_line_changes
    baseline_lines = index_lines_by_key(baseline_snapshot.snapshot_data['boq_lines'])
    comparison_lines = index_lines_by_key(comparison_snapshot.snapshot_data['boq_lines'])

    changes = {
      added: [],
      removed: [],
      modified: [],
      unchanged: []
    }

    # Find added lines
    (comparison_lines.keys - baseline_lines.keys).each do |key|
      changes[:added] << {
        key: key,
        line: comparison_lines[key],
        change_type: 'added'
      }
    end

    # Find removed lines
    (baseline_lines.keys - comparison_lines.keys).each do |key|
      changes[:removed] << {
        key: key,
        line: baseline_lines[key],
        change_type: 'removed'
      }
    end

    # Find modified lines
    (baseline_lines.keys & comparison_lines.keys).each do |key|
      baseline_line = baseline_lines[key]
      comparison_line = comparison_lines[key]

      if lines_different?(baseline_line, comparison_line)
        changes[:modified] << {
          key: key,
          baseline: baseline_line,
          comparison: comparison_line,
          differences: calculate_line_differences(baseline_line, comparison_line),
          change_type: 'modified'
        }
      else
        changes[:unchanged] << {
          key: key,
          line: comparison_line,
          change_type: 'unchanged'
        }
      end
    end

    changes
  end

  def analyze_quantity_changes
    baseline_quantities = index_quantities_by_element(baseline_snapshot.snapshot_data)
    comparison_quantities = index_quantities_by_element(comparison_snapshot.snapshot_data)

    quantity_changes = []

    comparison_quantities.each do |element_key, comparison_qty|
      baseline_qty = baseline_quantities[element_key]

      if baseline_qty.nil?
        # New quantity
        quantity_changes << {
          element_key: element_key,
          element_name: comparison_qty['element_name'],
          change_type: 'added',
          new_quantity: comparison_qty['quantity'],
          new_unit: comparison_qty['unit']
        }
      elsif quantities_different?(baseline_qty, comparison_qty)
        # Modified quantity
        quantity_changes << {
          element_key: element_key,
          element_name: comparison_qty['element_name'],
          change_type: 'modified',
          old_quantity: baseline_qty['quantity'],
          new_quantity: comparison_qty['quantity'],
          quantity_change: comparison_qty['quantity'] - baseline_qty['quantity'],
          quantity_change_percentage: calculate_percentage_change(
            baseline_qty['quantity'], 
            comparison_qty['quantity']
          ),
          unit: comparison_qty['unit']
        }
      end
    end

    # Find removed quantities
    baseline_quantities.each do |element_key, baseline_qty|
      unless comparison_quantities.key?(element_key)
        quantity_changes << {
          element_key: element_key,
          element_name: baseline_qty['element_name'],
          change_type: 'removed',
          old_quantity: baseline_qty['quantity'],
          old_unit: baseline_qty['unit']
        }
      end
    end

    quantity_changes
  end

  def analyze_rate_changes
    baseline_rates = index_rates(baseline_snapshot.snapshot_data)
    comparison_rates = index_rates(comparison_snapshot.snapshot_data)

    rate_changes = []

    comparison_rates.each do |rate_key, comparison_rate|
      baseline_rate = baseline_rates[rate_key]

      if baseline_rate.nil?
        # New rate
        rate_changes << {
          rate_key: rate_key,
          rate_description: comparison_rate['description'],
          change_type: 'added',
          new_rate: comparison_rate['rate_per_unit'],
          unit: comparison_rate['unit']
        }
      elsif rates_different?(baseline_rate, comparison_rate)
        # Modified rate
        rate_changes << {
          rate_key: rate_key,
          rate_description: comparison_rate['description'],
          change_type: 'modified',
          old_rate: baseline_rate['rate_per_unit'],
          new_rate: comparison_rate['rate_per_unit'],
          rate_change: comparison_rate['rate_per_unit'] - baseline_rate['rate_per_unit'],
          rate_change_percentage: calculate_percentage_change(
            baseline_rate['rate_per_unit'], 
            comparison_rate['rate_per_unit']
          ),
          unit: comparison_rate['unit'],
          affected_lines: find_affected_lines(rate_key, comparison_snapshot.snapshot_data)
        }
      end
    end

    rate_changes
  end

  def calculate_financial_impact
    baseline_total = baseline_snapshot.snapshot_data['total_value']
    comparison_total = comparison_snapshot.snapshot_data['total_value']

    {
      total_change: comparison_total - baseline_total,
      total_change_percentage: calculate_percentage_change(baseline_total, comparison_total),
      impact_by_category: calculate_category_impact,
      cost_variance: {
        favorable: comparison_total < baseline_total,
        variance_amount: (comparison_total - baseline_total).abs,
        variance_percentage: calculate_percentage_change(baseline_total, comparison_total).abs
      }
    }
  end

  def analyze_element_changes
    baseline_elements = index_elements(baseline_snapshot.snapshot_data)
    comparison_elements = index_elements(comparison_snapshot.snapshot_data)

    element_changes = []

    # Find modified elements
    comparison_elements.each do |element_key, comparison_element|
      baseline_element = baseline_elements[element_key]

      if baseline_element && elements_different?(baseline_element, comparison_element)
        element_changes << {
          element_key: element_key,
          element_name: comparison_element['name'],
          change_type: 'modified',
          changes: calculate_element_differences(baseline_element, comparison_element)
        }
      elsif baseline_element.nil?
        element_changes << {
          element_key: element_key,
          element_name: comparison_element['name'],
          change_type: 'added'
        }
      end
    end

    # Find removed elements
    baseline_elements.each do |element_key, baseline_element|
      unless comparison_elements.key?(element_key)
        element_changes << {
          element_key: element_key,
          element_name: baseline_element['name'],
          change_type: 'removed'
        }
      end
    end

    element_changes
  end

  # Helper methods

  def index_lines_by_key(lines)
    lines.index_by { |line| generate_line_key(line) }
  end

  def generate_line_key(line)
    "#{line['element_id']}_#{line['assembly_id']}"
  end

  def index_quantities_by_element(snapshot_data)
    quantities = {}
    snapshot_data['quantities'].each do |qty|
      key = "#{qty['element_id']}_#{qty['assembly_id']}"
      quantities[key] = qty
    end
    quantities
  end

  def index_rates(snapshot_data)
    snapshot_data['rates'].index_by { |rate| rate['id'] }
  end

  def index_elements(snapshot_data)
    snapshot_data['elements'].index_by { |element| element['id'] }
  end

  def lines_different?(line1, line2)
    %w[quantity total rate_per_unit].any? { |field| line1[field] != line2[field] }
  end

  def quantities_different?(qty1, qty2)
    qty1['quantity'] != qty2['quantity'] || qty1['unit'] != qty2['unit']
  end

  def rates_different?(rate1, rate2)
    rate1['rate_per_unit'] != rate2['rate_per_unit']
  end

  def elements_different?(element1, element2)
    %w[name specification_text extracted_data clarification_parameters].any? do |field|
      element1[field] != element2[field]
    end
  end

  def calculate_line_differences(baseline_line, comparison_line)
    differences = {}

    %w[quantity total rate_per_unit description].each do |field|
      if baseline_line[field] != comparison_line[field]
        differences[field] = {
          old_value: baseline_line[field],
          new_value: comparison_line[field],
          change: comparison_line[field] - baseline_line[field] rescue nil
        }
      end
    end

    differences
  end

  def calculate_element_differences(baseline_element, comparison_element)
    differences = {}

    %w[name specification_text].each do |field|
      if baseline_element[field] != comparison_element[field]
        differences[field] = {
          old_value: baseline_element[field],
          new_value: comparison_element[field]
        }
      end
    end

    # Deep compare extracted_data and clarification_parameters
    %w[extracted_data clarification_parameters].each do |field|
      baseline_data = baseline_element[field] || {}
      comparison_data = comparison_element[field] || {}

      if baseline_data != comparison_data
        differences[field] = calculate_hash_differences(baseline_data, comparison_data)
      end
    end

    differences
  end

  def calculate_hash_differences(hash1, hash2)
    all_keys = (hash1.keys + hash2.keys).uniq
    differences = {}

    all_keys.each do |key|
      if hash1[key] != hash2[key]
        differences[key] = {
          old_value: hash1[key],
          new_value: hash2[key]
        }
      end
    end

    differences
  end

  def calculate_percentage_change(old_value, new_value)
    return 0 if old_value.zero?
    ((new_value - old_value) / old_value.to_f) * 100
  end

  def calculate_category_impact
    # Group changes by NRM category and calculate impact
    impact_by_category = {}
    
    comparison_result[:line_changes][:modified].each do |change|
      category = change[:comparison]['nrm_category'] || 'Unknown'
      total_change = change[:differences]['total']&.dig('change') || 0
      
      impact_by_category[category] ||= 0
      impact_by_category[category] += total_change
    end

    impact_by_category
  end

  def find_affected_lines(rate_id, snapshot_data)
    snapshot_data['boq_lines'].select { |line| line['rate_id'] == rate_id }.map do |line|
      {
        line_id: line['id'],
        description: line['description'],
        quantity: line['quantity']
      }
    end
  end

  def count_major_changes
    # Count changes that represent significant financial impact (>5% or >£1000)
    major_changes = 0
    
    comparison_result[:line_changes][:modified].each do |change|
      total_change = change[:differences]['total']&.dig('change') || 0
      if total_change.abs > 1000 # Major if >£1000 change
        major_changes += 1
      end
    end

    major_changes
  end

  def count_minor_changes
    comparison_result[:line_changes][:modified].size - count_major_changes
  end

  def generate_csv_report
    CSV.generate(headers: true) do |csv|
      csv << [
        "Change Type", "Element/Line", "Description", "Old Value", "New Value", 
        "Change Amount", "Change %", "Financial Impact"
      ]

      # Add line changes
      comparison_result[:line_changes][:modified].each do |change|
        csv << [
          "Line Modified",
          change[:comparison]['description'],
          "BoQ Line Change",
          change[:baseline]['total'],
          change[:comparison]['total'],
          change[:differences]['total']&.dig('change'),
          calculate_percentage_change(change[:baseline]['total'], change[:comparison]['total']).round(2),
          change[:differences]['total']&.dig('change')
        ]
      end

      # Add quantity changes
      comparison_result[:quantity_changes].each do |change|
        csv << [
          "Quantity #{change[:change_type].capitalize}",
          change[:element_name],
          "Quantity Change",
          change[:old_quantity],
          change[:new_quantity],
          change[:quantity_change],
          change[:quantity_change_percentage]&.round(2),
          "TBD" # Would need to calculate based on affected lines
        ]
      end
    end
  end

  def generate_pdf_report
    # Would use a PDF library like Prawn to generate formatted comparison report
    "PDF generation would be implemented here using a library like Prawn"
  end
end
```

### 2. Snapshot Comparison Controller
```ruby
# app/controllers/snapshot_comparisons_controller.rb
class SnapshotComparisonsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_project
  before_action :set_snapshots

  def show
    authorize @baseline_snapshot
    authorize @comparison_snapshot

    @comparison_service = SnapshotComparisonService.new(@baseline_snapshot, @comparison_snapshot)
    @comparison_service.generate_comparison
    @comparison_result = @comparison_service.comparison_result

    respond_to do |format|
      format.html
      format.json { render json: @comparison_result }
    end
  end

  def export
    authorize @baseline_snapshot
    authorize @comparison_snapshot

    comparison_service = SnapshotComparisonService.new(@baseline_snapshot, @comparison_snapshot)
    comparison_service.generate_comparison

    format = params[:format]&.to_sym || :json
    
    case format
    when :csv
      send_data comparison_service.export_comparison_report(format: :csv),
                filename: "snapshot_comparison_#{Date.current}.csv",
                type: 'text/csv'
    when :pdf
      send_data comparison_service.export_comparison_report(format: :pdf),
                filename: "snapshot_comparison_#{Date.current}.pdf",
                type: 'application/pdf'
    else
      render json: comparison_service.export_comparison_report(format: :json)
    end
  end

  def timeline
    authorize @project, :show?

    @snapshots = @project.project_snapshots
                        .includes(:created_by)
                        .order(:created_at)

    @timeline_data = build_timeline_data(@snapshots)

    respond_to do |format|
      format.html
      format.json { render json: @timeline_data }
    end
  end

  private

  def set_project
    @project = current_account.projects.find(params[:project_id])
  end

  def set_snapshots
    @baseline_snapshot = @project.project_snapshots.find(params[:baseline_id])
    @comparison_snapshot = @project.project_snapshots.find(params[:comparison_id])
  end

  def build_timeline_data(snapshots)
    timeline_events = []

    snapshots.each_with_index do |snapshot, index|
      event = {
        id: snapshot.id,
        name: snapshot.name,
        date: snapshot.created_at,
        total_value: snapshot.total_value,
        created_by: snapshot.created_by&.name || "System",
        is_milestone: snapshot.is_milestone,
        element_count: snapshot.snapshot_data['elements']&.size || 0,
        line_count: snapshot.snapshot_data['boq_lines']&.size || 0
      }

      # Calculate change from previous snapshot
      if index > 0
        previous_snapshot = snapshots[index - 1]
        value_change = snapshot.total_value - previous_snapshot.total_value
        event[:value_change] = value_change
        event[:value_change_percentage] = 
          ((value_change / previous_snapshot.total_value) * 100).round(2) rescue 0
      end

      timeline_events << event
    end

    {
      project_id: @project.id,
      project_title: @project.title,
      timeline: timeline_events,
      summary: {
        total_snapshots: snapshots.count,
        date_range: {
          first: snapshots.first&.created_at,
          last: snapshots.last&.created_at
        },
        value_range: {
          min: snapshots.minimum(:total_value),
          max: snapshots.maximum(:total_value)
        }
      }
    }
  end
end
```

### 3. Comparison Interface View
```erb
<!-- app/views/snapshot_comparisons/show.html.erb -->
<% content_for :title, "Snapshot Comparison - #{@project.title}" %>

<div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
  <!-- Header -->
  <div class="mb-8">
    <div class="flex items-center justify-between">
      <div>
        <h1 class="text-2xl font-bold text-gray-900">Snapshot Comparison</h1>
        <p class="mt-1 text-sm text-gray-500">
          Comparing changes between two project snapshots
        </p>
      </div>
      
      <div class="flex space-x-3">
        <%= link_to "Export CSV", 
            snapshot_comparison_path(@project, baseline_id: @baseline_snapshot.id, comparison_id: @comparison_snapshot.id, format: :csv),
            class: "btn btn-secondary" %>
        <%= link_to "Export PDF", 
            snapshot_comparison_path(@project, baseline_id: @baseline_snapshot.id, comparison_id: @comparison_snapshot.id, format: :pdf),
            class: "btn btn-secondary" %>
        <%= link_to "Timeline View", 
            timeline_snapshot_comparisons_path(@project),
            class: "btn btn-outline" %>
      </div>
    </div>

    <!-- Snapshot Info -->
    <div class="mt-6 grid grid-cols-2 gap-6">
      <div class="bg-blue-50 rounded-lg p-4">
        <h3 class="text-sm font-medium text-blue-900">Baseline Snapshot</h3>
        <p class="mt-1 text-lg font-semibold text-blue-800"><%= @baseline_snapshot.name %></p>
        <p class="text-sm text-blue-600">
          <%= @baseline_snapshot.created_at.strftime("%B %d, %Y at %I:%M %p") %>
        </p>
        <p class="text-sm text-blue-600">
          Total Value: <%= number_to_currency(@baseline_snapshot.total_value) %>
        </p>
      </div>
      
      <div class="bg-green-50 rounded-lg p-4">
        <h3 class="text-sm font-medium text-green-900">Comparison Snapshot</h3>
        <p class="mt-1 text-lg font-semibold text-green-800"><%= @comparison_snapshot.name %></p>
        <p class="text-sm text-green-600">
          <%= @comparison_snapshot.created_at.strftime("%B %d, %Y at %I:%M %p") %>
        </p>
        <p class="text-sm text-green-600">
          Total Value: <%= number_to_currency(@comparison_snapshot.total_value) %>
        </p>
      </div>
    </div>
  </div>

  <!-- Summary Cards -->
  <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-8">
    <div class="bg-white rounded-lg border border-gray-200 p-4">
      <div class="flex items-center">
        <div class="flex-shrink-0">
          <div class="w-8 h-8 bg-blue-100 rounded-md flex items-center justify-center">
            <svg class="w-4 h-4 text-blue-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1" />
            </svg>
          </div>
        </div>
        <div class="ml-3">
          <p class="text-sm font-medium text-gray-500">Total Change</p>
          <p class="text-lg font-semibold <%= @comparison_result[:summary][:total_value_change] >= 0 ? 'text-green-600' : 'text-red-600' %>">
            <%= number_to_currency(@comparison_result[:summary][:total_value_change]) %>
          </p>
        </div>
      </div>
    </div>

    <div class="bg-white rounded-lg border border-gray-200 p-4">
      <div class="flex items-center">
        <div class="flex-shrink-0">
          <div class="w-8 h-8 bg-yellow-100 rounded-md flex items-center justify-center">
            <svg class="w-4 h-4 text-yellow-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 4V2a1 1 0 011-1h8a1 1 0 011 1v2m-9 0h10m-10 0v16a2 2 0 002 2h6a2 2 0 002-2V4" />
            </svg>
          </div>
        </div>
        <div class="ml-3">
          <p class="text-sm font-medium text-gray-500">Line Changes</p>
          <p class="text-lg font-semibold text-gray-900">
            <%= @comparison_result[:line_changes][:modified].size %>
          </p>
        </div>
      </div>
    </div>

    <div class="bg-white rounded-lg border border-gray-200 p-4">
      <div class="flex items-center">
        <div class="flex-shrink-0">
          <div class="w-8 h-8 bg-purple-100 rounded-md flex items-center justify-center">
            <svg class="w-4 h-4 text-purple-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
            </svg>
          </div>
        </div>
        <div class="ml-3">
          <p class="text-sm font-medium text-gray-500">Major Changes</p>
          <p class="text-lg font-semibold text-gray-900">
            <%= @comparison_result[:summary][:major_changes] %>
          </p>
        </div>
      </div>
    </div>

    <div class="bg-white rounded-lg border border-gray-200 p-4">
      <div class="flex items-center">
        <div class="flex-shrink-0">
          <div class="w-8 h-8 bg-gray-100 rounded-md flex items-center justify-center">
            <svg class="w-4 h-4 text-gray-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
            </svg>
          </div>
        </div>
        <div class="ml-3">
          <p class="text-sm font-medium text-gray-500">% Change</p>
          <p class="text-lg font-semibold <%= @comparison_result[:summary][:total_value_change_percentage] >= 0 ? 'text-green-600' : 'text-red-600' %>">
            <%= number_with_precision(@comparison_result[:summary][:total_value_change_percentage], precision: 1) %>%
          </p>
        </div>
      </div>
    </div>
  </div>

  <!-- Detailed Changes -->
  <div class="space-y-8">
    
    <!-- Line Changes -->
    <div class="bg-white shadow rounded-lg">
      <div class="px-6 py-4 border-b border-gray-200">
        <h3 class="text-lg font-medium text-gray-900">BoQ Line Changes</h3>
      </div>
      <div class="p-6">
        <%= render "line_changes_table", line_changes: @comparison_result[:line_changes] %>
      </div>
    </div>

    <!-- Quantity Changes -->
    <div class="bg-white shadow rounded-lg">
      <div class="px-6 py-4 border-b border-gray-200">
        <h3 class="text-lg font-medium text-gray-900">Quantity Changes</h3>
      </div>
      <div class="p-6">
        <%= render "quantity_changes_table", quantity_changes: @comparison_result[:quantity_changes] %>
      </div>
    </div>

    <!-- Rate Changes -->
    <div class="bg-white shadow rounded-lg">
      <div class="px-6 py-4 border-b border-gray-200">
        <h3 class="text-lg font-medium text-gray-900">Rate Changes</h3>
      </div>
      <div class="p-6">
        <%= render "rate_changes_table", rate_changes: @comparison_result[:rate_changes] %>
      </div>
    </div>

  </div>
</div>
```

### 4. Timeline View
```erb
<!-- app/views/snapshot_comparisons/timeline.html.erb -->
<% content_for :title, "Snapshot Timeline - #{@project.title}" %>

<div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
  <div class="mb-8">
    <h1 class="text-2xl font-bold text-gray-900">Project Snapshot Timeline</h1>
    <p class="mt-1 text-sm text-gray-500">
      Track project changes over time through snapshots
    </p>
  </div>

  <!-- Timeline -->
  <div class="flow-root">
    <ul class="-mb-8">
      <% @timeline_data[:timeline].each_with_index do |event, index| %>
        <li>
          <div class="relative pb-8">
            <% unless index == @timeline_data[:timeline].length - 1 %>
              <span class="absolute top-4 left-4 -ml-px h-full w-0.5 bg-gray-200" aria-hidden="true"></span>
            <% end %>
            
            <div class="relative flex space-x-3">
              <div>
                <span class="h-8 w-8 rounded-full <%= event[:is_milestone] ? 'bg-green-500' : 'bg-blue-500' %> flex items-center justify-center ring-8 ring-white">
                  <svg class="h-4 w-4 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <% if event[:is_milestone] %>
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 3v4M3 5h4M6 17v4m-2-2h4m5-16l2.286 6.857L21 12l-5.714 2.143L13 21l-2.286-6.857L5 12l5.714-2.143L13 3z" />
                    <% else %>
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 4V2a1 1 0 011-1h8a1 1 0 011 1v2m-9 0h10m-10 0v16a2 2 0 002 2h6a2 2 0 002-2V4" />
                    <% end %>
                  </svg>
                </span>
              </div>
              
              <div class="min-w-0 flex-1 pt-1.5 flex justify-between space-x-4">
                <div>
                  <p class="text-sm font-medium text-gray-900">
                    <%= event[:name] %>
                    <% if event[:is_milestone] %>
                      <span class="ml-2 inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                        Milestone
                      </span>
                    <% end %>
                  </p>
                  <p class="text-sm text-gray-500">
                    Created by <%= event[:created_by] %> • 
                    <%= event[:element_count] %> elements • 
                    <%= event[:line_count] %> BoQ lines
                  </p>
                  <p class="text-sm font-medium text-gray-900 mt-1">
                    Total Value: <%= number_to_currency(event[:total_value]) %>
                    <% if event[:value_change] %>
                      <span class="ml-2 text-xs <%= event[:value_change] >= 0 ? 'text-green-600' : 'text-red-600' %>">
                        (<%= event[:value_change] >= 0 ? '+' : '' %><%= number_to_currency(event[:value_change]) %>, 
                        <%= event[:value_change_percentage] >= 0 ? '+' : '' %><%= event[:value_change_percentage] %>%)
                      </span>
                    <% end %>
                  </p>
                </div>
                
                <div class="text-right text-sm whitespace-nowrap text-gray-500">
                  <time datetime="<%= event[:date].iso8601 %>">
                    <%= event[:date].strftime("%b %d, %Y") %>
                  </time>
                  <div class="mt-1">
                    <%= link_to "View", 
                        project_project_snapshot_path(@project, event[:id]), 
                        class: "text-blue-600 hover:text-blue-800 text-xs" %>
                    <% if @timeline_data[:timeline][index + 1] %>
                      | <%= link_to "Compare", 
                             snapshot_comparison_path(@project, 
                                                    baseline_id: @timeline_data[:timeline][index + 1][:id], 
                                                    comparison_id: event[:id]), 
                             class: "text-blue-600 hover:text-blue-800 text-xs" %>
                    <% end %>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </li>
      <% end %>
    </ul>
  </div>
</div>
```

## Technical Notes
- Side-by-side comparison enables easy visual identification of changes
- Detailed change detection tracks all modifications with precision
- Financial impact analysis quantifies the business effect of changes
- Timeline view provides historical context for project evolution
- Export functionality enables sharing and documentation of changes

## Definition of Done
- [ ] Comparison interface displays changes clearly
- [ ] Change detection accurately identifies all modifications
- [ ] Financial impact analysis provides meaningful insights
- [ ] Export functionality generates usable reports
- [ ] Timeline view shows project evolution effectively
- [ ] Performance is acceptable for large snapshots
- [ ] All tests pass with >90% coverage
- [ ] Code review completed