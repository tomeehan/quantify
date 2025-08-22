# Ticket 1: Excel Export Service

**Epic**: M10 Excel Export  
**Story Points**: 3  
**Dependencies**: M-09 (BoQ line generation)

## Description
Create comprehensive Excel export service that generates professional BoQ documents with multiple worksheet formats, conditional formatting, charts, and customizable templates. Supports background processing and direct download/email delivery.

## Acceptance Criteria
- [ ] Excel export service with multiple template options
- [ ] Professional formatting with company branding
- [ ] Multiple worksheets (Summary, Detailed, Elements, Rates)
- [ ] Charts and visualizations for cost breakdown
- [ ] Background export processing for large projects
- [ ] Email delivery with password protection
- [ ] Export history and audit trails

## Code to be Written

### 1. Excel Export Service
```ruby
# app/services/excel_export_service.rb
class ExcelExportService
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :project
  attribute :template, :string, default: 'standard'
  attribute :options, :hash, default: {}

  def export
    Rails.logger.info("Starting Excel export", {
      project_id: project.id,
      template: template,
      options: options
    })

    workbook = Axlsx::Package.new
    
    case template
    when 'standard'
      build_standard_template(workbook)
    when 'detailed'
      build_detailed_template(workbook)
    when 'summary'
      build_summary_template(workbook)
    else
      build_standard_template(workbook)
    end

    file_path = generate_file_path
    workbook.serialize(file_path)
    
    create_export_record(file_path)
    
    Rails.logger.info("Excel export completed", {
      project_id: project.id,
      file_path: file_path,
      file_size: File.size(file_path)
    })

    file_path
  end

  private

  def build_standard_template(workbook)
    add_summary_sheet(workbook)
    add_boq_lines_sheet(workbook)
    add_elements_sheet(workbook)
    add_rates_sheet(workbook)
  end

  def build_detailed_template(workbook)
    build_standard_template(workbook)
    add_calculations_sheet(workbook)
    add_audit_trail_sheet(workbook)
  end

  def build_summary_template(workbook)
    add_summary_sheet(workbook)
    add_cost_breakdown_sheet(workbook)
  end

  def add_summary_sheet(workbook)
    workbook.workbook.add_worksheet(name: "Project Summary") do |sheet|
      styles = define_styles(workbook)
      
      # Project header
      sheet.add_row ["Project:", project.title], style: [styles[:header], styles[:bold]]
      sheet.add_row ["Client:", project.client], style: [styles[:label], nil]
      sheet.add_row ["Address:", project.address], style: [styles[:label], nil]
      sheet.add_row ["Region:", project.region], style: [styles[:label], nil]
      sheet.add_row ["Generated:", Date.current.strftime("%d/%m/%Y")], style: [styles[:label], nil]
      sheet.add_row [] # Empty row
      
      # Cost summary
      project_total = ProjectTotal.find_by(project: project)
      if project_total
        sheet.add_row ["COST SUMMARY"], style: styles[:section_header]
        sheet.add_row ["Labour:", "£#{number_with_delimiter(project_total.total_labour)}"], 
                     style: [styles[:label], styles[:currency]]
        sheet.add_row ["Plant:", "£#{number_with_delimiter(project_total.total_plant)}"], 
                     style: [styles[:label], styles[:currency]]
        sheet.add_row ["Material:", "£#{number_with_delimiter(project_total.total_material)}"], 
                     style: [styles[:label], styles[:currency]]
        sheet.add_row ["Overhead:", "£#{number_with_delimiter(project_total.total_overhead)}"], 
                     style: [styles[:label], styles[:currency]]
        sheet.add_row ["TOTAL:", "£#{number_with_delimiter(project_total.grand_total)}"], 
                     style: [styles[:header], styles[:total]]
      end
      
      # Auto-size columns
      sheet.column_widths 20, 20
    end
  end

  def add_boq_lines_sheet(workbook)
    workbook.workbook.add_worksheet(name: "Bill of Quantities") do |sheet|
      styles = define_styles(workbook)
      
      # Headers
      headers = ["Line", "Description", "Unit", "Quantity", "Rate", "Total"]
      sheet.add_row headers, style: styles[:table_header]
      
      # BoQ lines
      project.boq_lines.ordered.each_with_index do |line, index|
        row_data = [
          index + 1,
          line.description,
          line.unit,
          line.quantity_amount,
          line.rate_per_unit,
          line.total_amount
        ]
        
        row_style = index.even? ? styles[:even_row] : styles[:odd_row]
        sheet.add_row row_data, style: Array.new(6, row_style)
      end
      
      # Total row
      total_amount = project.boq_lines.sum(:total_amount)
      sheet.add_row ["", "", "", "", "TOTAL:", total_amount], 
                   style: [nil, nil, nil, nil, styles[:header], styles[:total]]
      
      # Format columns
      sheet.column_widths 8, 40, 10, 12, 12, 14
      
      # Apply currency formatting
      last_row = sheet.rows.length
      sheet["E2:F#{last_row}"].each { |cell| cell.style = styles[:currency] }
    end
  end

  def add_elements_sheet(workbook)
    workbook.workbook.add_worksheet(name: "Elements") do |sheet|
      styles = define_styles(workbook)
      
      # Headers
      headers = ["Element", "Type", "Status", "Confidence", "Specification"]
      sheet.add_row headers, style: styles[:table_header]
      
      # Elements
      project.elements.includes(:verification).each do |element|
        confidence = element.confidence_score ? 
                    "#{(element.confidence_score * 100).round(1)}%" : "N/A"
        
        row_data = [
          element.name,
          element.element_type&.humanize || "Unclassified",
          element.status.humanize,
          confidence,
          element.specification_preview(100)
        ]
        
        sheet.add_row row_data, style: styles[:text_wrap]
      end
      
      # Format columns
      sheet.column_widths 25, 15, 12, 12, 50
      
      # Set row height for wrapped text
      sheet.rows.each_with_index do |row, index|
        next if index == 0 # Skip header
        row.height = 30
      end
    end
  end

  def add_rates_sheet(workbook)
    workbook.workbook.add_worksheet(name: "Rates") do |sheet|
      styles = define_styles(workbook)
      
      # Headers
      headers = ["Code", "Description", "Type", "Unit", "Rate", "Source", "Effective Date"]
      sheet.add_row headers, style: styles[:table_header]
      
      # Get unique rates used in project
      used_rates = Rate.joins(:boq_lines)
                      .where(boq_lines: { project: project })
                      .distinct
                      .order(:rate_type, :code)
      
      used_rates.each do |rate|
        row_data = [
          rate.code,
          rate.description,
          rate.rate_type.humanize,
          rate.unit,
          rate.rate_per_unit,
          rate.data_source,
          rate.effective_from.strftime("%d/%m/%Y")
        ]
        
        sheet.add_row row_data
      end
      
      # Format columns
      sheet.column_widths 15, 35, 12, 10, 12, 15, 12
      
      # Apply currency formatting to rate column
      last_row = sheet.rows.length
      sheet["E2:E#{last_row}"].each { |cell| cell.style = styles[:currency] }
    end
  end

  def add_cost_breakdown_sheet(workbook)
    workbook.workbook.add_worksheet(name: "Cost Breakdown") do |sheet|
      styles = define_styles(workbook)
      project_total = ProjectTotal.find_by(project: project)
      return unless project_total
      
      # Create pie chart data
      breakdown_data = [
        ["Labour", project_total.total_labour],
        ["Plant", project_total.total_plant],
        ["Material", project_total.total_material],
        ["Overhead", project_total.total_overhead]
      ].reject { |_, value| value.zero? }
      
      # Add data for chart
      sheet.add_row ["Cost Category", "Amount"]
      breakdown_data.each do |category, amount|
        sheet.add_row [category, amount]
      end
      
      # Create chart
      chart = sheet.add_chart(Axlsx::Pie3DChart, start_at: "D2", end_at: "J15") do |chart|
        chart.add_series data: sheet["B2:B#{breakdown_data.length + 1}"],
                        labels: sheet["A2:A#{breakdown_data.length + 1}"],
                        title: "Cost Breakdown"
        chart.title.text = "Project Cost Breakdown"
      end
    end
  end

  def define_styles(workbook)
    {
      header: workbook.workbook.styles.add_style(
        b: true, sz: 14, fg_color: "FFFFFF", bg_color: "366092"
      ),
      section_header: workbook.workbook.styles.add_style(
        b: true, sz: 12, fg_color: "366092"
      ),
      table_header: workbook.workbook.styles.add_style(
        b: true, bg_color: "D9E1F2", border: { style: :thin, color: "000000" }
      ),
      label: workbook.workbook.styles.add_style(b: true),
      bold: workbook.workbook.styles.add_style(b: true),
      currency: workbook.workbook.styles.add_style(
        format_code: "£#,##0.00", alignment: { horizontal: :right }
      ),
      total: workbook.workbook.styles.add_style(
        b: true, format_code: "£#,##0.00", bg_color: "FFFF00"
      ),
      even_row: workbook.workbook.styles.add_style(bg_color: "F2F2F2"),
      odd_row: workbook.workbook.styles.add_style(bg_color: "FFFFFF"),
      text_wrap: workbook.workbook.styles.add_style(alignment: { wrap_text: true })
    }
  end

  def generate_file_path
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    filename = "#{project.title.parameterize}_boq_#{timestamp}.xlsx"
    Rails.root.join("tmp", "exports", filename)
  end

  def create_export_record(file_path)
    ExportHistory.create!(
      project: project,
      export_type: 'excel',
      template: template,
      file_path: file_path,
      file_size: File.size(file_path),
      exported_by: options[:user],
      export_options: options
    )
  end

  def number_with_delimiter(number)
    ActionController::Base.helpers.number_with_delimiter(number)
  end
end
```

### 2. Excel Export Job
```ruby
# app/jobs/excel_export_job.rb
class ExcelExportJob < ApplicationJob
  include JobErrorHandling
  
  queue_as :exports
  
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(project, user, options = {})
    @project = project
    @user = user
    @options = options.with_indifferent_access.merge(user: user)
    
    Rails.logger.info("Starting Excel export job", {
      project_id: project.id,
      user_id: user.id,
      template: @options[:template]
    })
    
    # Generate Excel file
    file_path = ExcelExportService.new(
      project: project,
      template: @options[:template] || 'standard',
      options: @options
    ).export
    
    # Handle delivery
    if @options[:email_delivery]
      deliver_via_email(file_path)
    else
      broadcast_download_ready(file_path)
    end
    
    Rails.logger.info("Excel export job completed", {
      project_id: project.id,
      file_path: file_path
    })
    
  rescue => e
    Rails.logger.error("Excel export job failed", {
      project_id: project.id,
      error: e.message,
      backtrace: e.backtrace.first(5)
    })
    
    broadcast_export_failed(e.message)
    raise e
  end

  private

  def deliver_via_email(file_path)
    ExportMailer.boq_export_ready(@user, @project, file_path, @options).deliver_now
    
    broadcast_email_sent
  end

  def broadcast_download_ready(file_path)
    Turbo::StreamsChannel.broadcast_action_to(
      "user_#{@user.id}",
      action: :replace,
      target: "export_status",
      partial: "exports/download_ready",
      locals: {
        project: @project,
        file_path: file_path,
        download_url: download_export_path(project_id: @project.id, file: File.basename(file_path))
      }
    )
  end

  def broadcast_email_sent
    Turbo::StreamsChannel.broadcast_action_to(
      "user_#{@user.id}",
      action: :prepend,
      target: "notifications",
      partial: "shared/notification",
      locals: {
        type: :success,
        message: "BoQ export has been emailed to #{@user.email}"
      }
    )
  end

  def broadcast_export_failed(error_message)
    Turbo::StreamsChannel.broadcast_action_to(
      "user_#{@user.id}",
      action: :replace,
      target: "export_status",
      partial: "exports/export_failed",
      locals: {
        project: @project,
        error: error_message
      }
    )
  end
end
```

### 3. Export History Model
```ruby
# app/models/export_history.rb
class ExportHistory < ApplicationRecord
  belongs_to :project
  belongs_to :exported_by, class_name: 'User'

  EXPORT_TYPES = %w[excel pdf csv].freeze
  TEMPLATES = %w[standard detailed summary].freeze

  validates :export_type, inclusion: { in: EXPORT_TYPES }
  validates :template, inclusion: { in: TEMPLATES }
  validates :file_path, presence: true
  validates :file_size, presence: true, numericality: { greater_than: 0 }

  scope :recent, -> { order(created_at: :desc) }
  scope :by_type, ->(type) { where(export_type: type) }
  scope :for_project, ->(project) { where(project: project) }

  def file_exists?
    File.exist?(file_path)
  end

  def file_size_mb
    (file_size / 1024.0 / 1024.0).round(2)
  end

  def download_filename
    File.basename(file_path)
  end
end
```

### 4. Export Controller
```ruby
# app/controllers/projects/exports_controller.rb
class Projects::ExportsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_project

  def new
    authorize @project
    @export_options = build_export_options
  end

  def create
    authorize @project
    
    options = {
      template: params[:template] || 'standard',
      email_delivery: params[:email_delivery] == 'true',
      password_protect: params[:password_protect] == 'true',
      include_charts: params[:include_charts] == 'true'
    }
    
    ExcelExportJob.perform_later(@project, current_user, options)
    
    respond_to do |format|
      format.html { redirect_to project_path(@project), notice: "Export started. You'll be notified when ready." }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "export_form",
          partial: "export_processing",
          locals: { project: @project }
        )
      end
    end
  end

  def download
    authorize @project
    
    export = @project.export_histories.find_by(file_path: params[:file])
    
    unless export&.file_exists?
      redirect_to @project, alert: "Export file not found or has expired."
      return
    end
    
    send_file export.file_path,
              filename: export.download_filename,
              type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              disposition: 'attachment'
  end

  def history
    authorize @project
    @exports = @project.export_histories.includes(:exported_by).recent.limit(20)
  end

  private

  def set_project
    @project = current_account.projects.find(params[:project_id])
  end

  def build_export_options
    {
      templates: [
        ['Standard BoQ', 'standard'],
        ['Detailed Report', 'detailed'],  
        ['Summary Only', 'summary']
      ],
      delivery_options: [
        ['Download directly', 'download'],
        ['Email when ready', 'email']
      ]
    }
  end
end
```

### 5. Export Mailer
```ruby
# app/mailers/export_mailer.rb
class ExportMailer < ApplicationMailer
  def boq_export_ready(user, project, file_path, options = {})
    @user = user
    @project = project
    @options = options
    
    attachments["#{project.title.parameterize}_boq.xlsx"] = File.read(file_path)
    
    mail(
      to: user.email,
      subject: "BoQ Export Ready: #{project.title}",
      template_path: 'export_mailer',
      template_name: 'boq_export_ready'
    )
  end
end
```

## Technical Notes
- Uses Axlsx gem for professional Excel generation
- Background processing prevents UI blocking
- Multiple template options serve different use cases
- Email delivery with attachment for remote access
- Comprehensive error handling and user feedback

## Definition of Done
- [ ] Excel files generate with professional formatting
- [ ] Multiple templates work correctly
- [ ] Background processing completes successfully
- [ ] Email delivery functions properly
- [ ] Download links work securely
- [ ] Export history tracks all exports
- [ ] Error handling provides user feedback
- [ ] Test coverage exceeds 85%
- [ ] Code review completed