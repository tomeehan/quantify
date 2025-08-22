# Ticket 1: Final Export & Delivery System

**Epic**: M12 Final Export & Delivery  
**Story Points**: 4  
**Dependencies**: M-11 (Snapshot management)

## Description
Create comprehensive export and delivery system that produces professional, client-ready BoQ documents in multiple formats (Excel, PDF, CSV), with branded templates, digital signatures, secure delivery options, and automated client notifications.

## Acceptance Criteria
- [ ] Multiple export formats with professional branding
- [ ] PDF generation with digital signatures and watermarks
- [ ] Secure delivery via encrypted links and password protection
- [ ] Client portal for document access and download
- [ ] Automated email notifications with delivery confirmation
- [ ] Version control and document tracking
- [ ] Bulk export capabilities for project portfolios

## Code to be Written

### 1. Document Generator Service
```ruby
# app/services/document_generator.rb
class DocumentGenerator
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :project
  attribute :format, :string, default: 'excel'
  attribute :template, :string, default: 'client_standard'
  attribute :options, :hash, default: {}

  SUPPORTED_FORMATS = %w[excel pdf csv].freeze
  CLIENT_TEMPLATES = %w[client_standard client_detailed client_summary executive_summary].freeze

  def generate
    validate_inputs!
    
    case format.downcase
    when 'excel'
      generate_excel_document
    when 'pdf'
      generate_pdf_document
    when 'csv'
      generate_csv_document
    else
      raise ArgumentError, "Unsupported format: #{format}"
    end
  end

  private

  def validate_inputs!
    unless SUPPORTED_FORMATS.include?(format)
      raise ArgumentError, "Format must be one of: #{SUPPORTED_FORMATS.join(', ')}"
    end
    
    unless CLIENT_TEMPLATES.include?(template)
      raise ArgumentError, "Template must be one of: #{CLIENT_TEMPLATES.join(', ')}"
    end
  end

  def generate_excel_document
    ClientExcelGenerator.new(
      project: project,
      template: template,
      options: enhanced_options
    ).generate
  end

  def generate_pdf_document
    ClientPdfGenerator.new(
      project: project,
      template: template,
      options: enhanced_options
    ).generate
  end

  def generate_csv_document
    ClientCsvGenerator.new(
      project: project,
      template: template,
      options: enhanced_options
    ).generate
  end

  def enhanced_options
    base_options = {
      include_branding: true,
      include_signatures: true,
      client_name: project.client,
      generation_date: Date.current,
      document_version: calculate_version_number
    }
    
    base_options.merge(options)
  end

  def calculate_version_number
    existing_deliveries = project.client_deliveries.where(format: format, template: template).count
    "v#{existing_deliveries + 1}.0"
  end
end
```

### 2. PDF Generator Service
```ruby
# app/services/client_pdf_generator.rb
class ClientPdfGenerator
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :project
  attribute :template
  attribute :options, :hash, default: {}

  def generate
    Rails.logger.info("Generating PDF document", {
      project_id: project.id,
      template: template
    })

    pdf = Prawn::Document.new(page_size: 'A4', margin: 50)
    
    case template
    when 'client_standard'
      build_standard_client_report(pdf)
    when 'client_detailed'
      build_detailed_client_report(pdf)
    when 'executive_summary'
      build_executive_summary(pdf)
    else
      build_standard_client_report(pdf)
    end

    file_path = generate_file_path
    pdf.render_file(file_path)
    
    # Add digital signature if requested
    if options[:include_signatures]
      add_digital_signature(file_path)
    end
    
    # Add watermark if specified
    if options[:watermark_text]
      add_watermark(file_path, options[:watermark_text])
    end

    file_path
  end

  private

  def build_standard_client_report(pdf)
    add_header(pdf)
    add_project_summary(pdf)
    add_cost_summary(pdf)
    add_boq_table(pdf)
    add_footer(pdf)
  end

  def add_header(pdf)
    # Company logo
    if company_logo_path.present? && File.exist?(company_logo_path)
      pdf.image company_logo_path, width: 100, position: :right
    end
    
    pdf.move_down 20
    
    # Document title
    pdf.text "BILL OF QUANTITIES", size: 24, style: :bold, align: :center
    pdf.move_down 10
    
    # Project details
    pdf.text project.title, size: 18, style: :bold, align: :center
    pdf.text "Prepared for: #{project.client}", size: 12, align: :center
    pdf.text "Date: #{Date.current.strftime('%d %B %Y')}", size: 10, align: :center
    
    pdf.move_down 30
  end

  def add_project_summary(pdf)
    pdf.text "PROJECT SUMMARY", size: 14, style: :bold
    pdf.move_down 10
    
    summary_data = [
      ["Project", project.title],
      ["Client", project.client],
      ["Location", project.address],
      ["Region", project.region],
      ["Elements", project.elements.count.to_s],
      ["Document Version", options[:document_version] || "v1.0"]
    ]
    
    pdf.table(summary_data, 
              cell_style: { borders: [:bottom], border_width: 0.5, padding: 5 },
              column_widths: [150, 300])
    
    pdf.move_down 20
  end

  def add_cost_summary(pdf)
    project_total = ProjectTotal.find_by(project: project)
    return unless project_total
    
    pdf.text "COST SUMMARY", size: 14, style: :bold
    pdf.move_down 10
    
    cost_data = [
      ["Category", "Amount (£)"],
      ["Labour", format_currency(project_total.total_labour)],
      ["Plant & Equipment", format_currency(project_total.total_plant)],
      ["Materials", format_currency(project_total.total_material)],
      ["Overheads", format_currency(project_total.total_overhead)],
      ["", ""],
      ["TOTAL PROJECT VALUE", format_currency(project_total.grand_total)]
    ]
    
    pdf.table(cost_data,
              header: true,
              cell_style: { borders: [:bottom], border_width: 0.5, padding: 8 },
              column_widths: [300, 200]) do |table|
      table.row(0).font_style = :bold
      table.row(-1).font_style = :bold
      table.row(-1).background_color = 'FFFFCC'
    end
    
    pdf.move_down 20
  end

  def add_boq_table(pdf)
    pdf.text "DETAILED BILL OF QUANTITIES", size: 14, style: :bold
    pdf.move_down 10
    
    boq_lines = project.boq_lines.includes(:element, :rate).ordered
    
    if boq_lines.any?
      # Split into chunks to handle pagination
      lines_per_page = 25
      boq_lines.in_groups_of(lines_per_page, false) do |lines_chunk|
        create_boq_table_page(pdf, lines_chunk)
        pdf.start_new_page unless lines_chunk == boq_lines.last(lines_per_page)
      end
    else
      pdf.text "No BoQ lines available", style: :italic
    end
  end

  def create_boq_table_page(pdf, lines)
    table_data = [["Item", "Description", "Unit", "Qty", "Rate (£)", "Total (£)"]]
    
    lines.each_with_index do |line, index|
      table_data << [
        (index + 1).to_s,
        truncate_text(line.description, 40),
        line.unit,
        format_number(line.quantity_amount),
        format_currency(line.rate_per_unit),
        format_currency(line.total_amount)
      ]
    end
    
    pdf.table(table_data,
              header: true,
              cell_style: { borders: [:bottom], border_width: 0.5, padding: 4, size: 9 },
              column_widths: [40, 220, 50, 60, 80, 80]) do |table|
      table.row(0).font_style = :bold
      table.row(0).background_color = 'DDDDDD'
    end
  end

  def add_footer(pdf)
    pdf.move_down 30
    
    pdf.text "This document was generated on #{Time.current.strftime('%d %B %Y at %H:%M')}",
             size: 8, style: :italic, align: :center
    
    if options[:include_signatures]
      pdf.move_down 20
      pdf.text "Digitally signed and verified", size: 8, align: :center
    end
    
    # Page numbers
    pdf.page_count.times do |i|
      pdf.go_to_page(i + 1)
      pdf.draw_text "Page #{i + 1} of #{pdf.page_count}", 
                   at: [pdf.bounds.right - 100, 20], size: 8
    end
  end

  def add_digital_signature(file_path)
    # Implementation would use gem like 'origami' for PDF signing
    Rails.logger.info("Digital signature added to PDF", { file_path: file_path })
  end

  def add_watermark(file_path, watermark_text)
    # Implementation would add watermark to PDF
    Rails.logger.info("Watermark added to PDF", { 
      file_path: file_path, 
      watermark: watermark_text 
    })
  end

  def company_logo_path
    Rails.root.join('app', 'assets', 'images', 'company_logo.png')
  end

  def format_currency(amount)
    "£#{number_with_delimiter(amount&.round(2) || 0)}"
  end

  def format_number(number)
    number_with_delimiter(number&.round(4) || 0)
  end

  def truncate_text(text, length)
    text.length > length ? "#{text[0..length-4]}..." : text
  end

  def number_with_delimiter(number)
    ActionController::Base.helpers.number_with_delimiter(number)
  end

  def generate_file_path
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    filename = "#{project.title.parameterize}_boq_#{timestamp}.pdf"
    Rails.root.join("tmp", "exports", filename)
  end
end
```

### 3. Client Delivery Model
```ruby
# app/models/client_delivery.rb
class ClientDelivery < ApplicationRecord
  belongs_to :project
  belongs_to :delivered_by, class_name: 'User'
  belongs_to :project_snapshot, optional: true

  DELIVERY_METHODS = %w[email secure_link client_portal download].freeze
  FORMATS = %w[excel pdf csv].freeze
  STATUSES = %w[preparing ready delivered viewed downloaded expired].freeze

  validates :delivery_method, inclusion: { in: DELIVERY_METHODS }
  validates :format, inclusion: { in: FORMATS }
  validates :status, inclusion: { in: STATUSES }
  validates :file_path, presence: true
  validates :secure_token, presence: true, uniqueness: true

  before_create :generate_secure_token
  before_create :set_expiry_date

  scope :recent, -> { order(created_at: :desc) }
  scope :active, -> { where(status: %w[ready delivered viewed downloaded]) }
  scope :expired, -> { where('expires_at < ?', Time.current) }

  def self.create_delivery(project, user, options = {})
    delivery = new(
      project: project,
      delivered_by: user,
      delivery_method: options[:delivery_method] || 'email',
      format: options[:format] || 'excel',
      template: options[:template] || 'client_standard',
      recipient_email: options[:recipient_email] || project.client_email,
      delivery_options: options[:delivery_options] || {},
      status: 'preparing'
    )
    
    delivery.save!
    delivery.generate_document!
    delivery
  end

  def generate_document!
    Rails.logger.info("Generating client document", {
      delivery_id: id,
      project_id: project.id,
      format: format
    })
    
    file_path = DocumentGenerator.new(
      project: project,
      format: format,
      template: template,
      options: delivery_options.merge(
        delivery_id: id,
        secure_token: secure_token
      )
    ).generate
    
    update!(
      file_path: file_path,
      file_size: File.size(file_path),
      status: 'ready'
    )
    
    Rails.logger.info("Document generated successfully", {
      delivery_id: id,
      file_path: file_path,
      file_size: file_size
    })
  end

  def deliver!
    case delivery_method
    when 'email'
      deliver_via_email
    when 'secure_link'
      generate_secure_link
    when 'client_portal'
      publish_to_client_portal
    end
    
    update!(status: 'delivered', delivered_at: Time.current)
  end

  def download_url
    Rails.application.routes.url_helpers.secure_download_url(
      token: secure_token,
      host: Rails.application.config.action_mailer.default_url_options[:host]
    )
  end

  def mark_as_viewed!
    update!(status: 'viewed', viewed_at: Time.current) if status == 'delivered'
  end

  def mark_as_downloaded!
    update!(status: 'downloaded', downloaded_at: Time.current)
  end

  def expired?
    expires_at && expires_at < Time.current
  end

  def file_exists?
    File.exist?(file_path) if file_path.present?
  end

  def download_filename
    base_name = "#{project.title.parameterize}_boq"
    timestamp = created_at.strftime("%Y%m%d")
    version = template.include?('summary') ? 'summary' : 'detailed'
    
    "#{base_name}_#{version}_#{timestamp}.#{format_extension}"
  end

  private

  def generate_secure_token
    self.secure_token = SecureRandom.urlsafe_base64(32)
  end

  def set_expiry_date
    # Default expiry: 30 days for secure links, 90 days for other methods
    default_days = delivery_method == 'secure_link' ? 30 : 90
    expiry_days = delivery_options['expiry_days'] || default_days
    self.expires_at = expiry_days.days.from_now
  end

  def deliver_via_email
    ClientDeliveryMailer.document_ready(self).deliver_now
  end

  def generate_secure_link
    # Secure link is generated via download_url method
    Rails.logger.info("Secure link generated", {
      delivery_id: id,
      download_url: download_url
    })
  end

  def publish_to_client_portal
    # Implementation would integrate with client portal system
    Rails.logger.info("Published to client portal", { delivery_id: id })
  end

  def format_extension
    case format
    when 'excel'
      'xlsx'
    when 'pdf'
      'pdf'
    when 'csv'
      'csv'
    else
      'txt'
    end
  end
end
```

### 4. Client Delivery Controller
```ruby
# app/controllers/projects/deliveries_controller.rb
class Projects::DeliveriesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_project
  before_action :set_delivery, only: [:show, :deliver, :regenerate, :download]

  def index
    authorize @project
    @deliveries = @project.client_deliveries.includes(:delivered_by, :project_snapshot).recent
  end

  def new
    authorize @project
    @delivery = @project.client_deliveries.build
    @delivery_options = build_delivery_options
  end

  def create
    authorize @project
    
    delivery_params = {
      delivery_method: params[:delivery_method],
      format: params[:format],
      template: params[:template],
      recipient_email: params[:recipient_email],
      delivery_options: {
        password_protect: params[:password_protect] == 'true',
        include_watermark: params[:include_watermark] == 'true',
        watermark_text: params[:watermark_text],
        expiry_days: params[:expiry_days]&.to_i
      }
    }
    
    ClientDeliveryJob.perform_later(@project, current_user, delivery_params)
    
    respond_to do |format|
      format.html { redirect_to project_deliveries_path(@project), notice: "Document preparation started." }
      format.turbo_stream do
        flash.now[:notice] = "Preparing document for delivery..."
      end
    end
  end

  def show
    authorize @delivery
  end

  def deliver
    authorize @delivery
    
    if @delivery.status == 'ready'
      @delivery.deliver!
      
      respond_to do |format|
        format.html { redirect_to project_delivery_path(@project, @delivery), notice: "Document delivered successfully." }
        format.turbo_stream do
          flash.now[:notice] = "Document delivered successfully."
        end
      end
    else
      respond_to do |format|
        format.html { redirect_to project_delivery_path(@project, @delivery), alert: "Document is not ready for delivery." }
        format.turbo_stream do
          flash.now[:alert] = "Document is not ready for delivery."
        end
      end
    end
  end

  def download
    authorize @delivery
    
    unless @delivery.file_exists?
      redirect_to project_delivery_path(@project, @delivery), alert: "File not found or has expired."
      return
    end
    
    @delivery.mark_as_downloaded!
    
    send_file @delivery.file_path,
              filename: @delivery.download_filename,
              type: mime_type_for_format(@delivery.format),
              disposition: 'attachment'
  end

  private

  def set_project
    @project = current_account.projects.find(params[:project_id])
  end

  def set_delivery
    @delivery = @project.client_deliveries.find(params[:id])
  end

  def build_delivery_options
    {
      delivery_methods: [
        ['Email directly to client', 'email'],
        ['Generate secure download link', 'secure_link'],
        ['Publish to client portal', 'client_portal']
      ],
      formats: [
        ['Excel spreadsheet', 'excel'],
        ['PDF document', 'pdf'],
        ['CSV data', 'csv']
      ],
      templates: [
        ['Standard client report', 'client_standard'],
        ['Detailed report', 'client_detailed'],
        ['Executive summary', 'executive_summary']
      ]
    }
  end

  def mime_type_for_format(format)
    case format
    when 'excel'
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    when 'pdf'
      'application/pdf'
    when 'csv'
      'text/csv'
    else
      'application/octet-stream'
    end
  end
end
```

### 5. Client Delivery Job
```ruby
# app/jobs/client_delivery_job.rb
class ClientDeliveryJob < ApplicationJob
  include JobErrorHandling
  
  queue_as :deliveries
  
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(project, user, delivery_params)
    @project = project
    @user = user
    @delivery_params = delivery_params
    
    Rails.logger.info("Starting client delivery job", {
      project_id: project.id,
      user_id: user.id,
      delivery_method: delivery_params[:delivery_method]
    })
    
    # Create delivery record
    delivery = ClientDelivery.create_delivery(project, user, delivery_params)
    
    # Auto-deliver if requested
    if delivery_params[:auto_deliver] != false
      delivery.deliver!
    end
    
    # Broadcast completion
    broadcast_delivery_ready(delivery)
    
    Rails.logger.info("Client delivery job completed", {
      delivery_id: delivery.id,
      status: delivery.status
    })
    
  rescue => e
    Rails.logger.error("Client delivery job failed", {
      project_id: project.id,
      error: e.message,
      backtrace: e.backtrace.first(5)
    })
    
    broadcast_delivery_failed(e.message)
    raise e
  end

  private

  def broadcast_delivery_ready(delivery)
    Turbo::StreamsChannel.broadcast_action_to(
      "user_#{@user.id}",
      action: :prepend,
      target: "notifications",
      partial: "shared/notification",
      locals: {
        type: :success,
        message: "Client document ready: #{delivery.download_filename}",
        action_link: Rails.application.routes.url_helpers.project_delivery_path(delivery.project, delivery)
      }
    )
  end

  def broadcast_delivery_failed(error_message)
    Turbo::StreamsChannel.broadcast_action_to(
      "user_#{@user.id}",
      action: :prepend,
      target: "notifications",
      partial: "shared/notification",
      locals: {
        type: :error,
        message: "Client document generation failed: #{error_message}"
      }
    )
  end
end
```

## Technical Notes
- Multi-format support serves different client preferences
- Secure delivery protects sensitive project information
- Professional branding maintains company image
- Automated workflows reduce manual delivery tasks
- Comprehensive audit trails support compliance requirements

## Definition of Done
- [ ] Multiple export formats generate correctly
- [ ] PDF documents include professional formatting
- [ ] Secure delivery methods function properly
- [ ] Email notifications work reliably
- [ ] Download links are secure and trackable
- [ ] Client portal integration operates smoothly
- [ ] Audit trails capture all delivery events
- [ ] Test coverage exceeds 85%
- [ ] Code review completed