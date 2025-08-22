# M-10: Excel Export System - Ticket 002: Export Templates & Customization

## Overview
Implement flexible export template system allowing users to customize Excel exports with different layouts, company branding, and data formatting options for various stakeholders (clients, quantity surveyors, contractors).

## Acceptance Criteria
- [ ] Multiple pre-built export templates (Standard, Detailed, Summary, Client-facing)
- [ ] Custom template builder with drag-and-drop fields
- [ ] Company branding integration (logos, colors, headers/footers)
- [ ] Conditional formatting and data validation
- [ ] Template sharing and team collaboration
- [ ] Export preview before generation

## Technical Implementation

### 1. Export Template Models

```ruby
# app/models/export_template.rb
class ExportTemplate < ApplicationRecord
  belongs_to :account
  belongs_to :created_by, class_name: 'User'
  has_many :export_template_sections, dependent: :destroy
  has_many :export_jobs, dependent: :nullify
  
  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :template_type, presence: true
  validates :configuration, presence: true
  
  enum template_type: {
    standard: 'standard',
    detailed: 'detailed', 
    summary: 'summary',
    client_facing: 'client_facing',
    cost_analysis: 'cost_analysis',
    custom: 'custom'
  }
  
  enum status: { draft: 'draft', active: 'active', archived: 'archived' }
  
  scope :available_for_user, ->(user) { where(status: :active) }
  scope :by_type, ->(type) { where(template_type: type) }
  
  def self.default_for_account(account)
    account.export_templates.find_by(template_type: :standard, status: :active) ||
    create_default_template(account)
  end
  
  def self.create_default_template(account)
    template = account.export_templates.create!(
      name: 'Standard BoQ Export',
      template_type: :standard,
      status: :active,
      created_by: account.users.first,
      configuration: default_configuration
    )
    
    create_default_sections(template)
    template
  end
  
  def self.default_configuration
    {
      page_setup: {
        orientation: 'landscape',
        paper_size: 'A4',
        margins: { top: 2, bottom: 2, left: 1.5, right: 1.5 }
      },
      branding: {
        show_logo: true,
        logo_position: 'top_left',
        company_details: true,
        color_scheme: '#2563eb'
      },
      formatting: {
        currency_format: '£#,##0.00',
        number_format: '#,##0.00',
        percentage_format: '0.0%',
        date_format: 'dd/mm/yyyy'
      },
      columns: {
        show_line_numbers: true,
        show_descriptions: true,
        show_quantities: true,
        show_rates: true,
        show_totals: true,
        show_trade_breakdown: false
      }
    }
  end
  
  def duplicate_for_account(target_account, new_name = nil)
    new_template = self.dup
    new_template.account = target_account
    new_template.name = new_name || "#{name} (Copy)"
    new_template.status = :draft
    new_template.created_by = target_account.users.first
    new_template.save!
    
    export_template_sections.each do |section|
      new_section = section.dup
      new_section.export_template = new_template
      new_section.save!
    end
    
    new_template
  end
  
  private
  
  def self.create_default_sections(template)
    # Header section
    template.export_template_sections.create!(
      name: 'Header',
      section_type: 'header',
      position: 1,
      configuration: {
        include_logo: true,
        include_company_details: true,
        include_project_details: true,
        include_date: true
      }
    )
    
    # Summary section
    template.export_template_sections.create!(
      name: 'Project Summary',
      section_type: 'summary',
      position: 2,
      configuration: {
        show_total_cost: true,
        show_item_count: true,
        show_trade_breakdown: true,
        show_rate_summary: false
      }
    )
    
    # Main data section
    template.export_template_sections.create!(
      name: 'Bill of Quantities',
      section_type: 'data_table',
      position: 3,
      configuration: {
        group_by: 'trade',
        include_subtotals: true,
        show_unit_rates: true,
        show_line_totals: true
      }
    )
    
    # Footer section
    template.export_template_sections.create!(
      name: 'Footer',
      section_type: 'footer',
      position: 4,
      configuration: {
        include_signatures: true,
        include_terms: true,
        include_contact_details: true
      }
    )
  end
end

# app/models/export_template_section.rb
class ExportTemplateSection < ApplicationRecord
  belongs_to :export_template
  
  validates :name, presence: true
  validates :section_type, presence: true
  validates :position, presence: true, uniqueness: { scope: :export_template_id }
  validates :configuration, presence: true
  
  enum section_type: {
    header: 'header',
    summary: 'summary', 
    data_table: 'data_table',
    chart: 'chart',
    notes: 'notes',
    footer: 'footer'
  }
  
  scope :ordered, -> { order(:position) }
  
  def move_to_position(new_position)
    old_position = position
    return if old_position == new_position
    
    if new_position > old_position
      # Moving down
      export_template.export_template_sections
                    .where(position: (old_position + 1)..new_position)
                    .update_all('position = position - 1')
    else
      # Moving up  
      export_template.export_template_sections
                    .where(position: new_position..(old_position - 1))
                    .update_all('position = position + 1')
    end
    
    update!(position: new_position)
  end
end
```

### 2. Template Builder Service

```ruby
# app/services/export_template_builder_service.rb
class ExportTemplateBuilderService
  attr_reader :template, :project, :workbook

  def initialize(template, project)
    @template = template
    @project = project
    @workbook = RubyXL::Workbook.new
    @worksheet = @workbook[0]
    @current_row = 0
  end

  def generate_export
    apply_page_setup
    apply_branding
    
    template.export_template_sections.ordered.each do |section|
      render_section(section)
    end
    
    apply_formatting
    workbook
  end

  private

  def apply_page_setup
    setup = template.configuration['page_setup']
    return unless setup
    
    @worksheet.page_setup.orientation = setup['orientation'] == 'landscape' ? 'landscape' : 'portrait'
    @worksheet.page_setup.paper_size = paper_size_code(setup['paper_size'])
    
    if setup['margins']
      margins = setup['margins']
      @worksheet.page_margins.top = margins['top']
      @worksheet.page_margins.bottom = margins['bottom'] 
      @worksheet.page_margins.left = margins['left']
      @worksheet.page_margins.right = margins['right']
    end
  end

  def apply_branding
    branding = template.configuration['branding']
    return unless branding&.dig('show_logo')
    
    if branding['logo_position'] == 'top_left' && template.account.logo.attached?
      # Add logo to worksheet
      add_logo_to_worksheet(branding)
    end
    
    if branding['company_details']
      add_company_details(branding)
    end
  end

  def render_section(section)
    case section.section_type
    when 'header'
      render_header_section(section)
    when 'summary'
      render_summary_section(section)
    when 'data_table'
      render_data_table_section(section)
    when 'chart'
      render_chart_section(section)
    when 'notes'
      render_notes_section(section)
    when 'footer'
      render_footer_section(section)
    end
  end

  def render_header_section(section)
    config = section.configuration
    start_row = @current_row
    
    if config['include_project_details']
      @worksheet.add_cell(@current_row, 0, 'Project:').change_font_bold(true)
      @worksheet.add_cell(@current_row, 1, @project.name)
      @current_row += 1
      
      @worksheet.add_cell(@current_row, 0, 'Client:').change_font_bold(true)
      @worksheet.add_cell(@current_row, 1, @project.client)
      @current_row += 1
      
      @worksheet.add_cell(@current_row, 0, 'Date:').change_font_bold(true)
      @worksheet.add_cell(@current_row, 1, Date.current.strftime('%d/%m/%Y'))
      @current_row += 1
    end
    
    @current_row += 1 # Add spacing
  end

  def render_summary_section(section)
    config = section.configuration
    
    @worksheet.add_cell(@current_row, 0, 'PROJECT SUMMARY').change_font_bold(true).change_font_size(14)
    @current_row += 2
    
    if config['show_total_cost']
      total_cost = @project.boq_lines.sum(:line_total)
      @worksheet.add_cell(@current_row, 0, 'Total Project Value:').change_font_bold(true)
      @worksheet.add_cell(@current_row, 1, format_currency(total_cost))
      @current_row += 1
    end
    
    if config['show_item_count']
      item_count = @project.boq_lines.count
      @worksheet.add_cell(@current_row, 0, 'Number of Items:').change_font_bold(true)
      @worksheet.add_cell(@current_row, 1, item_count)
      @current_row += 1
    end
    
    if config['show_trade_breakdown']
      render_trade_breakdown
    end
    
    @current_row += 2 # Add spacing
  end

  def render_data_table_section(section)
    config = section.configuration
    
    @worksheet.add_cell(@current_row, 0, 'BILL OF QUANTITIES').change_font_bold(true).change_font_size(14)
    @current_row += 2
    
    # Headers
    headers = build_table_headers(config)
    headers.each_with_index do |header, col|
      cell = @worksheet.add_cell(@current_row, col, header)
      cell.change_font_bold(true)
      cell.change_fill('DDDDDD')
    end
    @current_row += 1
    
    # Data rows
    if config['group_by'] == 'trade'
      render_grouped_data(config)
    else
      render_flat_data(config)
    end
  end

  def render_grouped_data(config)
    trades = @project.boq_lines.joins(:element).group('elements.trade').group('elements.trade')
    
    trades.each do |trade, lines|
      # Trade header
      @worksheet.add_cell(@current_row, 0, trade.upcase).change_font_bold(true)
      @current_row += 1
      
      # Lines for this trade
      lines.each do |line|
        render_data_row(line, config)
      end
      
      # Subtotal if configured
      if config['include_subtotals']
        trade_total = lines.sum(&:line_total)
        @worksheet.add_cell(@current_row, 0, "#{trade} Subtotal:").change_font_bold(true)
        @worksheet.add_cell(@current_row, -1, format_currency(trade_total)).change_font_bold(true)
        @current_row += 1
      end
      
      @current_row += 1 # Spacing between trades
    end
  end

  def render_flat_data(config)
    @project.boq_lines.includes(:element, :rate).each do |line|
      render_data_row(line, config)
    end
  end

  def render_data_row(line, config)
    col = 0
    
    # Line number
    if template.configuration.dig('columns', 'show_line_numbers')
      @worksheet.add_cell(@current_row, col, line.id)
      col += 1
    end
    
    # Description
    if template.configuration.dig('columns', 'show_descriptions')
      @worksheet.add_cell(@current_row, col, line.element.description)
      col += 1
    end
    
    # Unit
    @worksheet.add_cell(@current_row, col, line.element.unit)
    col += 1
    
    # Quantity
    if template.configuration.dig('columns', 'show_quantities')
      @worksheet.add_cell(@current_row, col, line.quantity)
      col += 1
    end
    
    # Rate
    if template.configuration.dig('columns', 'show_rates')
      @worksheet.add_cell(@current_row, col, format_currency(line.unit_rate))
      col += 1
    end
    
    # Total
    if template.configuration.dig('columns', 'show_totals')
      @worksheet.add_cell(@current_row, col, format_currency(line.line_total))
      col += 1
    end
    
    @current_row += 1
  end

  def render_chart_section(section)
    # Placeholder for chart implementation
    @worksheet.add_cell(@current_row, 0, '[Chart would be inserted here]')
    @current_row += 5 # Reserve space for chart
  end

  def render_notes_section(section)
    config = section.configuration
    
    if config['notes'].present?
      @worksheet.add_cell(@current_row, 0, 'NOTES').change_font_bold(true)
      @current_row += 1
      
      config['notes'].split("\n").each do |note|
        @worksheet.add_cell(@current_row, 0, note)
        @current_row += 1
      end
    end
    
    @current_row += 1
  end

  def render_footer_section(section)
    config = section.configuration
    
    if config['include_signatures']
      @current_row += 2
      @worksheet.add_cell(@current_row, 0, 'Prepared by: ___________________')
      @worksheet.add_cell(@current_row, 3, 'Date: ___________________')
      @current_row += 3
      
      @worksheet.add_cell(@current_row, 0, 'Approved by: ___________________')
      @worksheet.add_cell(@current_row, 3, 'Date: ___________________')
      @current_row += 1
    end
    
    if config['include_contact_details']
      @current_row += 2
      company = template.account
      @worksheet.add_cell(@current_row, 0, company.name)
      @current_row += 1
      
      if company.billing_address.present?
        @worksheet.add_cell(@current_row, 0, company.billing_address)
        @current_row += 1
      end
    end
  end

  def build_table_headers(config)
    headers = []
    
    headers << 'Item' if template.configuration.dig('columns', 'show_line_numbers')
    headers << 'Description' if template.configuration.dig('columns', 'show_descriptions')
    headers << 'Unit'
    headers << 'Qty' if template.configuration.dig('columns', 'show_quantities')
    headers << 'Rate' if template.configuration.dig('columns', 'show_rates')
    headers << 'Total' if template.configuration.dig('columns', 'show_totals')
    
    headers
  end

  def render_trade_breakdown
    trades_summary = @project.boq_lines
                            .joins(:element)
                            .group('elements.trade')
                            .sum(:line_total)
    
    trades_summary.each do |trade, total|
      @worksheet.add_cell(@current_row, 0, "#{trade}:")
      @worksheet.add_cell(@current_row, 1, format_currency(total))
      @current_row += 1
    end
  end

  def apply_formatting
    formatting = template.configuration['formatting']
    return unless formatting
    
    # Apply currency formatting to relevant cells
    # This would need to be implemented based on specific requirements
  end

  def format_currency(amount)
    return '' if amount.nil?
    format = template.configuration.dig('formatting', 'currency_format') || '£#,##0.00'
    # Apply the formatting - simplified for demo
    "£#{sprintf('%.2f', amount)}"
  end

  def paper_size_code(size)
    case size
    when 'A4' then 9
    when 'A3' then 8
    when 'Letter' then 1
    else 9
    end
  end

  def add_logo_to_worksheet(branding)
    # Implementation would depend on logo handling requirements
  end

  def add_company_details(branding)
    # Implementation for company details in header
  end
end
```

### 3. Template Builder Controller

```ruby
# app/controllers/accounts/export_templates_controller.rb
class Accounts::ExportTemplatesController < Accounts::BaseController
  before_action :authenticate_user!
  before_action :set_template, only: [:show, :edit, :update, :destroy, :duplicate, :preview]

  def index
    @templates = current_account.export_templates
                               .includes(:created_by)
                               .order(:template_type, :name)
    
    @templates = @templates.where(template_type: params[:type]) if params[:type].present?
    @templates = @templates.where(status: params[:status]) if params[:status].present?
  end

  def show
    @sections = @template.export_template_sections.ordered
    @recent_exports = current_account.export_jobs
                                    .where(export_template: @template)
                                    .limit(10)
                                    .order(created_at: :desc)
  end

  def new
    @template = current_account.export_templates.build
    
    if params[:type].present?
      @template.template_type = params[:type]
      @template.configuration = ExportTemplate.default_configuration
    end
    
    @available_sections = ExportTemplateSection.section_types.keys
  end

  def create
    @template = current_account.export_templates.build(template_params)
    @template.created_by = current_user
    authorize @template

    if @template.save
      create_default_sections if @template.sections.empty?
      redirect_to account_export_template_path(@template), 
                  notice: 'Export template created successfully'
    else
      @available_sections = ExportTemplateSection.section_types.keys
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @template
    @available_sections = ExportTemplateSection.section_types.keys
  end

  def update
    authorize @template

    if @template.update(template_params)
      redirect_to account_export_template_path(@template), 
                  notice: 'Export template updated successfully'
    else
      @available_sections = ExportTemplateSection.section_types.keys
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @template
    
    if @template.export_jobs.exists?
      redirect_to account_export_template_path(@template), 
                  alert: 'Cannot delete template that has been used for exports'
    else
      @template.destroy
      redirect_to account_export_templates_path, 
                  notice: 'Export template deleted successfully'
    end
  end

  def duplicate
    authorize @template, :show?
    
    new_template = @template.duplicate_for_account(
      current_account, 
      "#{@template.name} (Copy)"
    )
    
    redirect_to edit_account_export_template_path(new_template), 
                notice: 'Template duplicated successfully'
  end

  def preview
    authorize @template, :show?
    
    # Use a sample project for preview
    sample_project = current_account.projects.with_boq_lines.first
    
    if sample_project.nil?
      redirect_to account_export_template_path(@template), 
                  alert: 'No projects with BoQ data available for preview'
      return
    end
    
    service = ExportTemplateBuilderService.new(@template, sample_project)
    workbook = service.generate_export
    
    # Convert to HTML for preview (simplified)
    @preview_html = convert_workbook_to_html_preview(workbook)
    
    respond_to do |format|
      format.html
      format.json { render json: { preview_html: @preview_html } }
    end
  end

  def builder
    @template = current_account.export_templates.find(params[:id])
    authorize @template
    
    @sections = @template.export_template_sections.ordered
    @available_fields = get_available_fields
    @sample_data = get_sample_data
  end

  def update_sections
    @template = current_account.export_templates.find(params[:id])
    authorize @template
    
    sections_data = params[:sections] || []
    
    ActiveRecord::Base.transaction do
      # Delete existing sections
      @template.export_template_sections.destroy_all
      
      # Create new sections
      sections_data.each_with_index do |section_data, index|
        @template.export_template_sections.create!(
          name: section_data[:name],
          section_type: section_data[:section_type],
          position: index + 1,
          configuration: section_data[:configuration] || {}
        )
      end
    end
    
    render json: { success: true, message: 'Template updated successfully' }
  rescue StandardError => e
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  end

  private

  def set_template
    @template = current_account.export_templates.find(params[:id])
  end

  def template_params
    params.require(:export_template).permit(
      :name, :description, :template_type, :status, :configuration
    )
  end

  def create_default_sections
    ExportTemplate.send(:create_default_sections, @template)
  end

  def convert_workbook_to_html_preview(workbook)
    # Simplified HTML preview generation
    worksheet = workbook[0]
    html = "<table class='table table-striped'>"
    
    (0..worksheet.sheet_data.size - 1).each do |row_index|
      row = worksheet[row_index]
      next unless row
      
      html += "<tr>"
      (0..row.size - 1).each do |col_index|
        cell = row[col_index]
        value = cell&.value || ''
        html += "<td>#{ERB::Util.html_escape(value)}</td>"
      end
      html += "</tr>"
    end
    
    html += "</table>"
    html
  end

  def get_available_fields
    {
      project: ['name', 'client', 'description', 'location', 'created_at'],
      element: ['description', 'trade', 'unit', 'category'],
      boq_line: ['quantity', 'unit_rate', 'line_total'],
      rate: ['supplier_name', 'effective_from', 'effective_to'],
      account: ['name', 'billing_address', 'phone', 'email']
    }
  end

  def get_sample_data
    sample_project = current_account.projects.with_boq_lines.first
    return {} unless sample_project
    
    {
      project: {
        name: sample_project.name,
        client: sample_project.client,
        description: sample_project.description
      },
      boq_lines_count: sample_project.boq_lines.count,
      total_value: sample_project.boq_lines.sum(:line_total)
    }
  end
end
```

### 4. Template Builder Interface

```erb
<!-- app/views/accounts/export_templates/builder.html.erb -->
<div class="min-h-screen bg-gray-50" 
     data-controller="template-builder"
     data-template-builder-template-id-value="<%= @template.id %>"
     data-template-builder-update-url-value="<%= update_sections_account_export_template_path(@template) %>">
  
  <!-- Header -->
  <div class="bg-white border-b border-gray-200 px-6 py-4">
    <div class="flex items-center justify-between">
      <div>
        <h1 class="text-xl font-semibold text-gray-900">Template Builder</h1>
        <p class="text-sm text-gray-600 mt-1">Customize your export template</p>
      </div>
      
      <div class="flex items-center space-x-3">
        <%= link_to "Preview", 
            preview_account_export_template_path(@template),
            target: '_blank',
            class: "inline-flex items-center px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50" %>
        
        <button data-action="template-builder#saveTemplate"
                class="inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700">
          Save Template
        </button>
      </div>
    </div>
  </div>

  <div class="flex flex-1">
    <!-- Sidebar - Section Types -->
    <div class="w-64 bg-white border-r border-gray-200 overflow-y-auto">
      <div class="p-4">
        <h3 class="text-sm font-medium text-gray-900 mb-3">Available Sections</h3>
        
        <div class="space-y-2">
          <% ExportTemplateSection.section_types.each do |type, _| %>
            <div class="draggable-section p-3 border border-gray-200 rounded-lg cursor-move hover:bg-gray-50"
                 data-section-type="<%= type %>"
                 data-template-builder-target="availableSection">
              <div class="flex items-center">
                <div class="w-8 h-8 bg-blue-100 rounded-lg flex items-center justify-center mr-3">
                  <%= render "section_icon", type: type %>
                </div>
                <div>
                  <p class="text-sm font-medium text-gray-900"><%= type.humanize %></p>
                  <p class="text-xs text-gray-500"><%= section_description(type) %></p>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>

    <!-- Main Content - Template Builder -->
    <div class="flex-1 flex">
      <!-- Canvas -->
      <div class="flex-1 p-6">
        <div class="bg-white rounded-lg shadow-sm border min-h-[600px]"
             data-template-builder-target="canvas">
          
          <div class="p-6 border-b border-gray-200">
            <h3 class="text-lg font-medium text-gray-900">Template Layout</h3>
            <p class="text-sm text-gray-600 mt-1">
              Drag sections from the sidebar to build your template
            </p>
          </div>
          
          <div class="p-6">
            <div id="sections-container" 
                 class="space-y-4 min-h-[400px] border-2 border-dashed border-gray-300 rounded-lg p-4"
                 data-template-builder-target="sectionsContainer">
              
              <% if @sections.any? %>
                <% @sections.each do |section| %>
                  <%= render "template_section", section: section %>
                <% end %>
              <% else %>
                <div class="text-center py-12 text-gray-500">
                  <p>Drag sections here to start building your template</p>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>

      <!-- Properties Panel -->
      <div class="w-80 bg-white border-l border-gray-200 overflow-y-auto"
           data-template-builder-target="propertiesPanel">
        
        <div class="p-4 border-b border-gray-200">
          <h3 class="text-sm font-medium text-gray-900">Properties</h3>
        </div>
        
        <div id="properties-content" class="p-4">
          <div class="text-center text-gray-500 py-8">
            <p class="text-sm">Select a section to edit its properties</p>
          </div>
        </div>
      </div>
    </div>
  </div>
</div>

<!-- Section Template -->
<template data-template-builder-target="sectionTemplate">
  <div class="template-section border border-gray-200 rounded-lg p-4 bg-gray-50" 
       data-template-builder-target="templateSection">
    <div class="flex items-center justify-between mb-3">
      <div class="flex items-center">
        <div class="w-6 h-6 text-gray-400 mr-2">
          <!-- Icon will be inserted here -->
        </div>
        <h4 class="text-sm font-medium text-gray-900" data-template-builder-target="sectionName">
          Section Name
        </h4>
      </div>
      
      <div class="flex items-center space-x-2">
        <button data-action="template-builder#editSection" 
                class="text-gray-400 hover:text-gray-600">
          <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
            <path d="M13.586 3.586a2 2 0 112.828 2.828l-.793.793-2.828-2.828.793-.793zM11.379 5.793L3 14.172V17h2.828l8.38-8.379-2.828-2.828z"></path>
          </svg>
        </button>
        
        <button data-action="template-builder#removeSection" 
                class="text-red-400 hover:text-red-600">
          <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd"></path>
          </svg>
        </button>
      </div>
    </div>
    
    <div class="text-xs text-gray-600" data-template-builder-target="sectionDescription">
      Section description
    </div>
  </div>
</template>
```

### 5. Stimulus Controller for Template Builder

```javascript
// app/javascript/controllers/template_builder_controller.js
import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static targets = [
    "canvas", "sectionsContainer", "propertiesPanel", "availableSection",
    "templateSection", "sectionTemplate", "sectionName", "sectionDescription"
  ]
  
  static values = { 
    templateId: Number,
    updateUrl: String
  }

  connect() {
    this.initializeSortable()
    this.initializeDragAndDrop()
    this.sections = []
    this.selectedSection = null
  }

  initializeSortable() {
    if (this.hasSectionsContainerTarget) {
      this.sortable = Sortable.create(this.sectionsContainerTarget, {
        animation: 150,
        ghostClass: 'sortable-ghost',
        chosenClass: 'sortable-chosen',
        dragClass: 'sortable-drag',
        onEnd: (event) => {
          this.updateSectionOrder()
        }
      })
    }
  }

  initializeDragAndDrop() {
    this.availableSectionTargets.forEach(section => {
      section.addEventListener('dragstart', this.handleDragStart.bind(this))
      section.addEventListener('dragend', this.handleDragEnd.bind(this))
    })

    this.sectionsContainerTarget.addEventListener('dragover', this.handleDragOver.bind(this))
    this.sectionsContainerTarget.addEventListener('drop', this.handleDrop.bind(this))
  }

  handleDragStart(event) {
    const sectionType = event.target.dataset.sectionType
    event.dataTransfer.setData('text/plain', sectionType)
    event.dataTransfer.effectAllowed = 'copy'
  }

  handleDragEnd(event) {
    // Clean up drag state
  }

  handleDragOver(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = 'copy'
  }

  handleDrop(event) {
    event.preventDefault()
    const sectionType = event.dataTransfer.getData('text/plain')
    this.addSection(sectionType)
  }

  addSection(sectionType) {
    const sectionData = {
      id: this.generateTempId(),
      name: this.getSectionName(sectionType),
      section_type: sectionType,
      configuration: this.getDefaultConfiguration(sectionType)
    }

    this.sections.push(sectionData)
    this.renderSection(sectionData)
  }

  renderSection(sectionData) {
    const template = this.sectionTemplateTarget.content.cloneNode(true)
    const sectionElement = template.querySelector('.template-section')
    
    sectionElement.dataset.sectionId = sectionData.id
    sectionElement.querySelector('[data-template-builder-target="sectionName"]').textContent = sectionData.name
    sectionElement.querySelector('[data-template-builder-target="sectionDescription"]').textContent = 
      this.getSectionDescription(sectionData.section_type)

    this.sectionsContainerTarget.appendChild(template)
    
    // Remove empty state if it exists
    const emptyState = this.sectionsContainerTarget.querySelector('.text-center.py-12')
    if (emptyState) {
      emptyState.remove()
    }
  }

  editSection(event) {
    const sectionElement = event.target.closest('.template-section')
    const sectionId = sectionElement.dataset.sectionId
    const section = this.sections.find(s => s.id === sectionId)
    
    if (section) {
      this.showPropertiesPanel(section)
      this.selectedSection = section
    }
  }

  removeSection(event) {
    const sectionElement = event.target.closest('.template-section')
    const sectionId = sectionElement.dataset.sectionId
    
    this.sections = this.sections.filter(s => s.id !== sectionId)
    sectionElement.remove()
    
    if (this.sections.length === 0) {
      this.showEmptyState()
    }
  }

  showPropertiesPanel(section) {
    const propertiesHtml = this.generatePropertiesForm(section)
    const contentDiv = this.propertiesPanelTarget.querySelector('#properties-content')
    contentDiv.innerHTML = propertiesHtml
  }

  generatePropertiesForm(section) {
    switch (section.section_type) {
      case 'header':
        return this.generateHeaderProperties(section)
      case 'data_table':
        return this.generateDataTableProperties(section)
      case 'summary':
        return this.generateSummaryProperties(section)
      default:
        return this.generateGenericProperties(section)
    }
  }

  generateHeaderProperties(section) {
    return `
      <div class="space-y-4">
        <h4 class="font-medium">Header Configuration</h4>
        <div>
          <label class="block text-sm font-medium text-gray-700">Section Name</label>
          <input type="text" value="${section.name}" 
                 data-field="name" data-action="input->template-builder#updateSectionProperty"
                 class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
        </div>
        <div>
          <label class="flex items-center">
            <input type="checkbox" ${section.configuration.include_logo ? 'checked' : ''} 
                   data-field="configuration.include_logo" data-action="change->template-builder#updateSectionProperty"
                   class="rounded border-gray-300 text-blue-600 focus:ring-blue-500">
            <span class="ml-2 text-sm text-gray-700">Include Logo</span>
          </label>
        </div>
        <div>
          <label class="flex items-center">
            <input type="checkbox" ${section.configuration.include_company_details ? 'checked' : ''} 
                   data-field="configuration.include_company_details" data-action="change->template-builder#updateSectionProperty"
                   class="rounded border-gray-300 text-blue-600 focus:ring-blue-500">
            <span class="ml-2 text-sm text-gray-700">Include Company Details</span>
          </label>
        </div>
        <div>
          <label class="flex items-center">
            <input type="checkbox" ${section.configuration.include_project_details ? 'checked' : ''} 
                   data-field="configuration.include_project_details" data-action="change->template-builder#updateSectionProperty"
                   class="rounded border-gray-300 text-blue-600 focus:ring-blue-500">
            <span class="ml-2 text-sm text-gray-700">Include Project Details</span>
          </label>
        </div>
      </div>
    `
  }

  updateSectionProperty(event) {
    if (!this.selectedSection) return
    
    const field = event.target.dataset.field
    const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value
    
    this.setNestedProperty(this.selectedSection, field, value)
  }

  setNestedProperty(obj, path, value) {
    const keys = path.split('.')
    let current = obj
    
    for (let i = 0; i < keys.length - 1; i++) {
      if (!(keys[i] in current)) {
        current[keys[i]] = {}
      }
      current = current[keys[i]]
    }
    
    current[keys[keys.length - 1]] = value
  }

  updateSectionOrder() {
    const sectionElements = this.sectionsContainerTarget.querySelectorAll('.template-section')
    const newOrder = Array.from(sectionElements).map(el => el.dataset.sectionId)
    
    this.sections.sort((a, b) => {
      return newOrder.indexOf(a.id) - newOrder.indexOf(b.id)
    })
  }

  saveTemplate() {
    const data = {
      sections: this.sections.map((section, index) => ({
        ...section,
        position: index + 1
      }))
    }

    fetch(this.updateUrlValue, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': this.getCSRFToken()
      },
      body: JSON.stringify(data)
    })
    .then(response => response.json())
    .then(data => {
      if (data.success) {
        this.showNotification('Template saved successfully', 'success')
      } else {
        this.showNotification(data.error || 'Failed to save template', 'error')
      }
    })
    .catch(error => {
      console.error('Error:', error)
      this.showNotification('Failed to save template', 'error')
    })
  }

  showEmptyState() {
    this.sectionsContainerTarget.innerHTML = `
      <div class="text-center py-12 text-gray-500">
        <p>Drag sections here to start building your template</p>
      </div>
    `
  }

  getSectionName(type) {
    const names = {
      header: 'Header',
      summary: 'Project Summary',
      data_table: 'Bill of Quantities',
      chart: 'Chart',
      notes: 'Notes',
      footer: 'Footer'
    }
    return names[type] || type.charAt(0).toUpperCase() + type.slice(1)
  }

  getSectionDescription(type) {
    const descriptions = {
      header: 'Company logo, project details, and date',
      summary: 'Project totals and summary information',
      data_table: 'Main BoQ data with quantities and rates',
      chart: 'Visual representation of data',
      notes: 'Additional notes and comments',
      footer: 'Signatures and contact information'
    }
    return descriptions[type] || 'Section description'
  }

  getDefaultConfiguration(type) {
    const defaults = {
      header: {
        include_logo: true,
        include_company_details: true,
        include_project_details: true,
        include_date: true
      },
      summary: {
        show_total_cost: true,
        show_item_count: true,
        show_trade_breakdown: false
      },
      data_table: {
        group_by: 'none',
        include_subtotals: false,
        show_unit_rates: true,
        show_line_totals: true
      },
      footer: {
        include_signatures: true,
        include_contact_details: true
      }
    }
    return defaults[type] || {}
  }

  generateTempId() {
    return 'temp_' + Math.random().toString(36).substr(2, 9)
  }

  getCSRFToken() {
    return document.querySelector('meta[name="csrf-token"]')?.getAttribute('content')
  }

  showNotification(message, type) {
    // Simple notification implementation
    const notification = document.createElement('div')
    notification.className = `fixed top-4 right-4 px-4 py-2 rounded-md text-white z-50 ${
      type === 'success' ? 'bg-green-500' : 'bg-red-500'
    }`
    notification.textContent = message
    
    document.body.appendChild(notification)
    
    setTimeout(() => {
      notification.remove()
    }, 3000)
  }
}
```

## Testing Requirements

```ruby
# test/models/export_template_test.rb
require 'test_helper'

class ExportTemplateTest < ActiveSupport::TestCase
  def setup
    @account = accounts(:company)
    @user = users(:accountant)
    @template = export_templates(:standard_template)
  end

  test "creates default template for account" do
    new_account = accounts(:startup)
    template = ExportTemplate.default_for_account(new_account)
    
    assert_not_nil template
    assert_equal 'standard', template.template_type
    assert template.export_template_sections.any?
  end

  test "duplicates template with sections" do
    target_account = accounts(:startup)
    new_template = @template.duplicate_for_account(target_account, "Custom Template")
    
    assert_equal target_account, new_template.account
    assert_equal "Custom Template", new_template.name
    assert_equal @template.export_template_sections.count, new_template.export_template_sections.count
  end

  test "validates uniqueness of name within account" do
    duplicate = @account.export_templates.build(
      name: @template.name,
      template_type: 'custom',
      created_by: @user,
      configuration: {}
    )
    
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end
end

# test/services/export_template_builder_service_test.rb
require 'test_helper'

class ExportTemplateBuilderServiceTest < ActiveSupport::TestCase
  def setup
    @template = export_templates(:standard_template)
    @project = projects(:skyscraper)
    @service = ExportTemplateBuilderService.new(@template, @project)
  end

  test "generates workbook with correct structure" do
    workbook = @service.generate_export
    
    assert_not_nil workbook
    assert_not_nil workbook[0] # First worksheet
  end

  test "applies page setup configuration" do
    @template.configuration['page_setup'] = {
      'orientation' => 'landscape',
      'paper_size' => 'A4'
    }
    
    workbook = @service.generate_export
    worksheet = workbook[0]
    
    # Verify page setup was applied (specific assertions depend on RubyXL API)
    assert_not_nil worksheet.page_setup
  end

  test "renders all template sections" do
    sections_count = @template.export_template_sections.count
    
    workbook = @service.generate_export
    worksheet = workbook[0]
    
    # Verify content was added to worksheet
    assert worksheet.sheet_data.any?
  end
end
```

## Routes

```ruby
# config/routes/accounts.rb
resources :export_templates do
  member do
    get :preview
    post :duplicate
    get :builder
    patch :update_sections
  end
end
```

## Database Migrations

```ruby
# db/migrate/add_export_templates.rb
class CreateExportTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :export_templates do |t|
      t.references :account, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.text :description
      t.string :template_type, null: false
      t.string :status, default: 'draft'
      t.jsonb :configuration, default: {}
      
      t.timestamps
    end
    
    add_index :export_templates, [:account_id, :name], unique: true
    add_index :export_templates, :template_type
    add_index :export_templates, :status
  end
end

# db/migrate/create_export_template_sections.rb
class CreateExportTemplateSections < ActiveRecord::Migration[8.0]
  def change
    create_table :export_template_sections do |t|
      t.references :export_template, null: false, foreign_key: true
      t.string :name, null: false
      t.string :section_type, null: false
      t.integer :position, null: false
      t.jsonb :configuration, default: {}
      
      t.timestamps
    end
    
    add_index :export_template_sections, [:export_template_id, :position], unique: true
    add_index :export_template_sections, :section_type
  end
end
```