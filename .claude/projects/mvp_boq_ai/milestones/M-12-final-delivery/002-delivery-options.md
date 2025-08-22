# Ticket 2: Client Delivery & Portal Integration

**Epic**: M12 Final Export & Delivery  
**Story Points**: 6  
**Dependencies**: 001-final-export-delivery.md

## Description
Implement comprehensive delivery options for final BoQ documents including secure client portals, email delivery with digital signatures, automated notifications, and client collaboration features for BoQ review and approval.

## Acceptance Criteria
- [ ] Secure client portal for BoQ access and download
- [ ] Email delivery with digital signatures and encryption
- [ ] Automated delivery notifications and tracking
- [ ] Client review and approval workflow
- [ ] Document versioning and access control
- [ ] Delivery audit trail and compliance logging
- [ ] Mobile-optimized client access

## Code to be Written

### 1. Client Portal Model
```ruby
# app/models/client_portal.rb
class ClientPortal < ApplicationRecord
  belongs_to :project
  belongs_to :client_contact, class_name: 'User', optional: true
  has_many :portal_sessions, dependent: :destroy
  has_many :document_accesses, dependent: :destroy
  has_many :client_communications, dependent: :destroy

  validates :portal_url, presence: true, uniqueness: true
  validates :access_token, presence: true, uniqueness: true
  validates :expires_at, presence: true

  enum status: { active: 0, expired: 1, revoked: 2, suspended: 3 }
  enum access_level: { view_only: 0, download_enabled: 1, comment_enabled: 2, approval_enabled: 3 }

  before_create :generate_portal_credentials
  before_create :set_default_expiration

  scope :active_portals, -> { where(status: :active).where('expires_at > ?', Time.current) }

  def self.create_for_project(project, options = {})
    portal = new(
      project: project,
      client_name: options[:client_name] || project.client,
      client_email: options[:client_email],
      access_level: options[:access_level] || :download_enabled,
      custom_message: options[:custom_message],
      expires_at: options[:expires_at] || 30.days.from_now
    )
    
    portal.save!
    portal
  end

  def generate_access_link
    "#{Rails.application.routes.url_helpers.client_portal_url(portal_url, host: Rails.application.config.application_host)}"
  end

  def record_access(ip_address, user_agent)
    portal_sessions.create!(
      accessed_at: Time.current,
      ip_address: ip_address,
      user_agent: user_agent,
      session_duration: 0 # Will be updated when session ends
    )
  end

  def record_document_access(document_type, document_id, action)
    document_accesses.create!(
      document_type: document_type,
      document_id: document_id,
      access_action: action,
      accessed_at: Time.current
    )
  end

  def active?
    status == 'active' && expires_at > Time.current
  end

  def revoke_access!(reason = nil)
    update!(
      status: :revoked,
      revoked_at: Time.current,
      revocation_reason: reason
    )
  end

  def extend_access!(additional_days)
    update!(
      expires_at: expires_at + additional_days.days,
      extended_at: Time.current
    )
  end

  def usage_statistics
    {
      total_sessions: portal_sessions.count,
      unique_ips: portal_sessions.distinct.count(:ip_address),
      total_document_accesses: document_accesses.count,
      last_accessed: portal_sessions.maximum(:accessed_at),
      downloads_count: document_accesses.where(access_action: 'download').count,
      views_count: document_accesses.where(access_action: 'view').count
    }
  end

  private

  def generate_portal_credentials
    self.portal_url = SecureRandom.urlsafe_base64(32)
    self.access_token = SecureRandom.urlsafe_base64(64)
  end

  def set_default_expiration
    self.expires_at ||= 30.days.from_now
  end
end
```

### 2. Document Delivery Service
```ruby
# app/services/document_delivery_service.rb
class DocumentDeliveryService
  include ActiveModel::Model

  attr_reader :project, :delivery_options, :delivery_record

  def initialize(project, delivery_options = {})
    @project = project
    @delivery_options = delivery_options.with_indifferent_access
    @delivery_record = nil
  end

  def deliver_documents
    @delivery_record = create_delivery_record
    
    case delivery_options[:method]
    when 'email'
      deliver_via_email
    when 'portal'
      deliver_via_portal
    when 'secure_link'
      deliver_via_secure_link
    when 'combined'
      deliver_via_combined_method
    else
      raise ArgumentError, "Unsupported delivery method: #{delivery_options[:method]}"
    end

    finalize_delivery
    delivery_record
  end

  private

  def create_delivery_record
    DocumentDelivery.create!(
      project: project,
      delivery_method: delivery_options[:method],
      recipient_email: delivery_options[:recipient_email],
      recipient_name: delivery_options[:recipient_name],
      delivery_options: delivery_options,
      status: 'preparing',
      initiated_by: delivery_options[:initiated_by],
      initiated_at: Time.current
    )
  end

  def deliver_via_email
    # Generate documents
    documents = generate_delivery_documents

    # Create digital signatures if required
    if delivery_options[:digital_signature]
      documents = apply_digital_signatures(documents)
    end

    # Encrypt documents if required
    if delivery_options[:encryption]
      documents = encrypt_documents(documents)
    end

    # Send email with attachments
    delivery_result = DocumentDeliveryMailer.deliver_documents(
      project: project,
      recipient_email: delivery_options[:recipient_email],
      recipient_name: delivery_options[:recipient_name],
      documents: documents,
      custom_message: delivery_options[:custom_message],
      delivery_record: delivery_record
    ).deliver_now

    update_delivery_status('email_sent', {
      message_id: delivery_result.message_id,
      documents_included: documents.keys
    })

  rescue => error
    handle_delivery_error(error)
  end

  def deliver_via_portal
    # Create client portal
    portal = ClientPortal.create_for_project(project, {
      client_name: delivery_options[:recipient_name],
      client_email: delivery_options[:recipient_email],
      access_level: delivery_options[:access_level] || 'download_enabled',
      custom_message: delivery_options[:custom_message],
      expires_at: delivery_options[:expires_at]
    })

    # Generate and store documents in portal
    documents = generate_delivery_documents
    store_documents_in_portal(portal, documents)

    # Send portal access notification
    ClientPortalMailer.portal_access_notification(
      portal: portal,
      custom_message: delivery_options[:custom_message]
    ).deliver_now

    update_delivery_status('portal_created', {
      portal_id: portal.id,
      portal_url: portal.generate_access_link,
      documents_count: documents.count
    })

  rescue => error
    handle_delivery_error(error)
  end

  def deliver_via_secure_link
    # Generate secure download links with expiration
    documents = generate_delivery_documents
    secure_links = create_secure_download_links(documents)

    # Send secure link notification
    SecureLinkMailer.secure_download_notification(
      project: project,
      recipient_email: delivery_options[:recipient_email],
      recipient_name: delivery_options[:recipient_name],
      secure_links: secure_links,
      expires_at: delivery_options[:link_expires_at] || 7.days.from_now,
      custom_message: delivery_options[:custom_message]
    ).deliver_now

    update_delivery_status('secure_links_sent', {
      links_count: secure_links.count,
      expires_at: delivery_options[:link_expires_at]
    })

  rescue => error
    handle_delivery_error(error)
  end

  def deliver_via_combined_method
    # Deliver via both email and portal for maximum accessibility
    deliver_via_email
    deliver_via_portal

    update_delivery_status('combined_delivery_complete', {
      email_sent: true,
      portal_created: true
    })

  rescue => error
    handle_delivery_error(error)
  end

  def generate_delivery_documents
    documents = {}

    # Generate BoQ documents in various formats
    if delivery_options[:include_excel]
      documents[:excel] = ExcelExportService.new(project).generate_export
    end

    if delivery_options[:include_pdf]
      documents[:pdf] = PdfExportService.new(project).generate_export
    end

    if delivery_options[:include_summary]
      documents[:summary] = ProjectSummaryService.new(project).generate_summary
    end

    # Include additional documents if specified
    if delivery_options[:include_specifications]
      documents[:specifications] = SpecificationExportService.new(project).generate_export
    end

    if delivery_options[:include_calculations]
      documents[:calculations] = CalculationBreakdownService.new(project).generate_breakdown
    end

    documents
  end

  def apply_digital_signatures(documents)
    signed_documents = {}
    
    documents.each do |format, document_data|
      signed_documents[format] = DigitalSignatureService.new(
        document: document_data,
        signer: delivery_options[:signer] || project.account,
        certificate: delivery_options[:certificate]
      ).sign_document
    end

    signed_documents
  end

  def encrypt_documents(documents)
    encrypted_documents = {}
    
    documents.each do |format, document_data|
      encrypted_documents[format] = DocumentEncryptionService.new(
        document: document_data,
        encryption_key: delivery_options[:encryption_key],
        recipient_email: delivery_options[:recipient_email]
      ).encrypt_document
    end

    encrypted_documents
  end

  def store_documents_in_portal(portal, documents)
    documents.each do |format, document_data|
      PortalDocument.create!(
        client_portal: portal,
        document_type: format,
        document_name: "#{project.title}_BoQ.#{format}",
        document_data: document_data,
        file_size: document_data.bytesize,
        uploaded_at: Time.current
      )
    end
  end

  def create_secure_download_links(documents)
    secure_links = {}
    
    documents.each do |format, document_data|
      # Store document temporarily with secure token
      secure_document = SecureDocument.create!(
        project: project,
        document_type: format,
        document_name: "#{project.title}_BoQ.#{format}",
        document_data: document_data,
        access_token: SecureRandom.urlsafe_base64(64),
        expires_at: delivery_options[:link_expires_at] || 7.days.from_now,
        download_limit: delivery_options[:download_limit] || 10
      )

      secure_links[format] = {
        url: secure_download_url(secure_document.access_token),
        expires_at: secure_document.expires_at,
        download_limit: secure_document.download_limit
      }
    end

    secure_links
  end

  def update_delivery_status(status, metadata = {})
    delivery_record.update!(
      status: status,
      completed_at: Time.current,
      delivery_metadata: delivery_record.delivery_metadata.merge(metadata)
    )
  end

  def finalize_delivery
    # Send confirmation to internal team
    DeliveryConfirmationMailer.delivery_completed(
      delivery_record: delivery_record,
      project: project
    ).deliver_later

    # Create audit trail entry
    DocumentDeliveryAudit.create!(
      document_delivery: delivery_record,
      project: project,
      action: 'delivery_completed',
      metadata: {
        delivery_method: delivery_options[:method],
        recipient: delivery_options[:recipient_email],
        documents_delivered: delivery_record.delivery_metadata.dig('documents_included') || [],
        completion_time: Time.current
      }
    )
  end

  def handle_delivery_error(error)
    Rails.logger.error "Document delivery failed for project #{project.id}: #{error.message}"
    
    delivery_record.update!(
      status: 'failed',
      error_message: error.message,
      failed_at: Time.current
    )

    # Notify administrators
    DeliveryErrorMailer.delivery_failed(
      delivery_record: delivery_record,
      error: error
    ).deliver_now

    raise error
  end

  def secure_download_url(token)
    Rails.application.routes.url_helpers.secure_download_url(
      token, 
      host: Rails.application.config.application_host
    )
  end
end
```

### 3. Client Portal Controller
```ruby
# app/controllers/client_portals_controller.rb
class ClientPortalsController < ApplicationController
  skip_before_action :authenticate_user!
  before_action :find_portal_by_url
  before_action :validate_portal_access
  before_action :record_portal_access

  def show
    @project = @portal.project
    @documents = @portal.portal_documents.order(:created_at)
    @usage_stats = @portal.usage_statistics
    
    # Check if client contact exists
    @client_contact = @portal.client_contact
    
    respond_to do |format|
      format.html
      format.json {
        render json: {
          project: project_summary,
          documents: document_list,
          portal_info: portal_info
        }
      }
    end
  end

  def download_document
    document = @portal.portal_documents.find(params[:document_id])
    
    # Record download access
    @portal.record_document_access(
      document.document_type,
      document.id,
      'download'
    )

    # Track download in audit
    DocumentDownloadAudit.create!(
      portal_document: document,
      client_portal: @portal,
      downloaded_at: Time.current,
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )

    send_data document.document_data,
              filename: document.document_name,
              type: document.content_type,
              disposition: 'attachment'
  end

  def view_document
    document = @portal.portal_documents.find(params[:document_id])
    
    # Record view access
    @portal.record_document_access(
      document.document_type,
      document.id,
      'view'
    )

    case document.document_type
    when 'pdf'
      send_data document.document_data,
                filename: document.document_name,
                type: 'application/pdf',
                disposition: 'inline'
    when 'excel'
      # For Excel, redirect to download since inline viewing isn't practical
      redirect_to download_document_client_portal_path(@portal.portal_url, document)
    else
      render plain: "Document preview not available for this format"
    end
  end

  def submit_feedback
    feedback = @portal.client_communications.create!(
      communication_type: 'feedback',
      subject: params[:subject],
      message: params[:message],
      sender_name: params[:sender_name],
      sender_email: params[:sender_email],
      created_at: Time.current,
      metadata: {
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      }
    )

    # Notify project team
    ClientFeedbackMailer.new_feedback_received(
      feedback: feedback,
      portal: @portal
    ).deliver_later

    respond_to do |format|
      format.json { render json: { success: true, message: "Feedback submitted successfully" } }
      format.html { 
        flash[:notice] = "Thank you for your feedback!"
        redirect_to client_portal_path(@portal.portal_url)
      }
    end
  end

  def approve_boq
    return unless @portal.access_level == 'approval_enabled'

    approval = @portal.client_communications.create!(
      communication_type: 'approval',
      subject: 'BoQ Approval',
      message: params[:approval_message],
      sender_name: params[:approver_name],
      sender_email: params[:approver_email],
      approval_status: params[:approval_status], # 'approved' or 'rejected'
      created_at: Time.current,
      metadata: {
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        approval_timestamp: Time.current.iso8601
      }
    )

    # Update project approval status
    @portal.project.update!(
      client_approval_status: params[:approval_status],
      client_approved_at: Time.current,
      client_approval_notes: params[:approval_message]
    )

    # Notify project team
    ClientApprovalMailer.approval_received(
      approval: approval,
      portal: @portal
    ).deliver_now

    respond_to do |format|
      format.json { render json: { success: true, message: "Approval submitted successfully" } }
      format.html { 
        flash[:notice] = "Your approval has been recorded. Thank you!"
        redirect_to client_portal_path(@portal.portal_url)
      }
    end
  end

  private

  def find_portal_by_url
    @portal = ClientPortal.find_by(portal_url: params[:portal_url])
    
    unless @portal
      render_portal_not_found
      return false
    end
  end

  def validate_portal_access
    unless @portal.active?
      case @portal.status
      when 'expired'
        render_portal_expired
      when 'revoked'
        render_portal_revoked
      when 'suspended'
        render_portal_suspended
      else
        render_portal_not_available
      end
      return false
    end

    # Additional security checks
    if request.remote_ip.present? && @portal.ip_restrictions.present?
      allowed_ips = @portal.ip_restrictions
      unless allowed_ips.include?(request.remote_ip)
        render_access_denied("IP address not authorized")
        return false
      end
    end

    true
  end

  def record_portal_access
    @portal.record_access(request.remote_ip, request.user_agent)
  end

  def project_summary
    {
      id: @project.id,
      title: @project.title,
      client: @project.client,
      address: @project.address,
      region: @project.region,
      total_value: @project.total_cost,
      created_at: @project.created_at,
      last_updated: @project.updated_at
    }
  end

  def document_list
    @documents.map do |doc|
      {
        id: doc.id,
        name: doc.document_name,
        type: doc.document_type,
        size: doc.file_size,
        uploaded_at: doc.uploaded_at,
        download_url: download_document_client_portal_path(@portal.portal_url, doc),
        view_url: doc.document_type == 'pdf' ? view_document_client_portal_path(@portal.portal_url, doc) : nil
      }
    end
  end

  def portal_info
    {
      portal_name: @portal.client_name,
      access_level: @portal.access_level,
      expires_at: @portal.expires_at,
      custom_message: @portal.custom_message,
      can_download: @portal.access_level.in?(['download_enabled', 'comment_enabled', 'approval_enabled']),
      can_comment: @portal.access_level.in?(['comment_enabled', 'approval_enabled']),
      can_approve: @portal.access_level == 'approval_enabled'
    }
  end

  def render_portal_not_found
    render 'errors/portal_not_found', status: :not_found, layout: 'client_portal'
  end

  def render_portal_expired
    render 'errors/portal_expired', status: :gone, layout: 'client_portal'
  end

  def render_portal_revoked
    render 'errors/portal_revoked', status: :forbidden, layout: 'client_portal'
  end

  def render_portal_suspended
    render 'errors/portal_suspended', status: :forbidden, layout: 'client_portal'
  end

  def render_portal_not_available
    render 'errors/portal_not_available', status: :service_unavailable, layout: 'client_portal'
  end

  def render_access_denied(message)
    render 'errors/access_denied', locals: { message: message }, status: :forbidden, layout: 'client_portal'
  end
end
```

### 4. Client Portal View
```erb
<!-- app/views/client_portals/show.html.erb -->
<% content_for :title, "#{@project.title} - BoQ Documents" %>

<!DOCTYPE html>
<html>
<head>
  <title><%= content_for :title %></title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <%= csrf_meta_tags %>
  <%= csp_meta_tag %>
  <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
  <%= javascript_importmap_tags %>
</head>

<body class="bg-gray-50">
  <!-- Header -->
  <header class="bg-white shadow">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
      <div class="flex justify-between items-center py-6">
        <div class="flex items-center">
          <div class="flex-shrink-0">
            <!-- Company logo would go here -->
            <div class="h-8 w-8 bg-blue-600 rounded-md flex items-center justify-center">
              <span class="text-white font-bold text-sm">BoQ</span>
            </div>
          </div>
          <div class="ml-4">
            <h1 class="text-xl font-semibold text-gray-900"><%= @project.title %></h1>
            <p class="text-sm text-gray-500">Client: <%= @project.client %></p>
          </div>
        </div>
        
        <div class="text-right">
          <p class="text-sm text-gray-500">Portal expires:</p>
          <p class="text-sm font-medium text-gray-900">
            <%= @portal.expires_at.strftime("%B %d, %Y") %>
          </p>
        </div>
      </div>
    </div>
  </header>

  <!-- Main Content -->
  <main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
    
    <!-- Welcome Message -->
    <% if @portal.custom_message.present? %>
      <div class="bg-blue-50 border border-blue-200 rounded-md p-4 mb-8">
        <div class="flex">
          <div class="flex-shrink-0">
            <svg class="h-5 w-5 text-blue-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
          </div>
          <div class="ml-3">
            <p class="text-sm text-blue-800">
              <%= simple_format(@portal.custom_message) %>
            </p>
          </div>
        </div>
      </div>
    <% end %>

    <!-- Project Summary -->
    <div class="bg-white shadow rounded-lg mb-8">
      <div class="px-6 py-4 border-b border-gray-200">
        <h2 class="text-lg font-medium text-gray-900">Project Summary</h2>
      </div>
      <div class="px-6 py-4">
        <dl class="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <div>
            <dt class="text-sm font-medium text-gray-500">Project Address</dt>
            <dd class="mt-1 text-sm text-gray-900"><%= @project.address %></dd>
          </div>
          <div>
            <dt class="text-sm font-medium text-gray-500">Region</dt>
            <dd class="mt-1 text-sm text-gray-900"><%= @project.region %></dd>
          </div>
          <div>
            <dt class="text-sm font-medium text-gray-500">Total Project Value</dt>
            <dd class="mt-1 text-lg font-semibold text-gray-900">
              <%= number_to_currency(@project.total_cost) %>
            </dd>
          </div>
        </dl>
      </div>
    </div>

    <!-- Documents Section -->
    <div class="bg-white shadow rounded-lg mb-8">
      <div class="px-6 py-4 border-b border-gray-200">
        <h2 class="text-lg font-medium text-gray-900">BoQ Documents</h2>
        <p class="mt-1 text-sm text-gray-500">
          Download or view the Bill of Quantities documents for this project
        </p>
      </div>
      <div class="px-6 py-4">
        <% if @documents.any? %>
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <% @documents.each do |document| %>
              <div class="border border-gray-200 rounded-lg p-4 hover:border-gray-300 transition-colors">
                <div class="flex items-center justify-between mb-3">
                  <div class="flex items-center space-x-2">
                    <div class="flex-shrink-0">
                      <%= render "document_icon", document_type: document.document_type %>
                    </div>
                    <div>
                      <h3 class="text-sm font-medium text-gray-900">
                        <%= document.document_name %>
                      </h3>
                      <p class="text-xs text-gray-500">
                        <%= number_to_human_size(document.file_size) %>
                      </p>
                    </div>
                  </div>
                </div>

                <div class="flex space-x-2">
                  <% if document.document_type == 'pdf' %>
                    <%= link_to "View", 
                        view_document_client_portal_path(@portal.portal_url, document),
                        class: "flex-1 inline-flex justify-center items-center px-3 py-2 border border-gray-300 shadow-sm text-xs font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50",
                        target: "_blank" %>
                  <% end %>
                  
                  <%= link_to "Download", 
                      download_document_client_portal_path(@portal.portal_url, document),
                      class: "flex-1 inline-flex justify-center items-center px-3 py-2 border border-transparent text-xs font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700" %>
                </div>

                <p class="mt-2 text-xs text-gray-500">
                  Available since <%= document.uploaded_at.strftime("%B %d, %Y") %>
                </p>
              </div>
            <% end %>
          </div>
        <% else %>
          <div class="text-center py-8">
            <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
            </svg>
            <h3 class="mt-2 text-sm font-medium text-gray-900">No documents available</h3>
            <p class="mt-1 text-sm text-gray-500">
              Documents will appear here when they become available.
            </p>
          </div>
        <% end %>
      </div>
    </div>

    <!-- Feedback Section -->
    <% if @portal.access_level.in?(['comment_enabled', 'approval_enabled']) %>
      <div class="bg-white shadow rounded-lg mb-8">
        <div class="px-6 py-4 border-b border-gray-200">
          <h2 class="text-lg font-medium text-gray-900">Feedback & Questions</h2>
          <p class="mt-1 text-sm text-gray-500">
            Share your feedback or ask questions about the BoQ
          </p>
        </div>
        <div class="px-6 py-4">
          <%= form_with url: submit_feedback_client_portal_path(@portal.portal_url), 
                        method: :post, 
                        data: { controller: "feedback-form" } do |form| %>
            <div class="space-y-4">
              <div>
                <%= form.label :sender_name, "Your Name", class: "block text-sm font-medium text-gray-700" %>
                <%= form.text_field :sender_name, 
                    class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm",
                    required: true %>
              </div>

              <div>
                <%= form.label :sender_email, "Email Address", class: "block text-sm font-medium text-gray-700" %>
                <%= form.email_field :sender_email, 
                    class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm",
                    required: true %>
              </div>

              <div>
                <%= form.label :subject, "Subject", class: "block text-sm font-medium text-gray-700" %>
                <%= form.text_field :subject, 
                    class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm",
                    placeholder: "Brief description of your feedback or question" %>
              </div>

              <div>
                <%= form.label :message, "Message", class: "block text-sm font-medium text-gray-700" %>
                <%= form.text_area :message, 
                    rows: 4,
                    class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm",
                    placeholder: "Please provide your detailed feedback or questions...",
                    required: true %>
              </div>

              <div class="flex justify-end">
                <%= form.submit "Send Feedback", 
                    class: "inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500" %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    <% end %>

    <!-- Approval Section -->
    <% if @portal.access_level == 'approval_enabled' %>
      <div class="bg-white shadow rounded-lg">
        <div class="px-6 py-4 border-b border-gray-200">
          <h2 class="text-lg font-medium text-gray-900">BoQ Approval</h2>
          <p class="mt-1 text-sm text-gray-500">
            Please review the documents and provide your approval status
          </p>
        </div>
        <div class="px-6 py-4">
          <%= render "approval_form", portal: @portal, project: @project %>
        </div>
      </div>
    <% end %>

  </main>

  <!-- Footer -->
  <footer class="bg-white border-t border-gray-200 mt-12">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
      <div class="flex justify-between items-center">
        <p class="text-xs text-gray-500">
          This is a secure document portal. Access expires on <%= @portal.expires_at.strftime("%B %d, %Y") %>.
        </p>
        <p class="text-xs text-gray-400">
          Powered by BoQ AI Platform
        </p>
      </div>
    </div>
  </footer>
</body>
</html>
```

## Technical Notes
- Secure client portals with token-based authentication and access control
- Digital signatures and encryption ensure document integrity and security
- Comprehensive audit trails track all client interactions and document access
- Mobile-optimized interface provides excellent user experience across devices
- Automated notifications keep all stakeholders informed of delivery status

## Definition of Done
- [ ] Client portal provides secure document access
- [ ] Email delivery with digital signatures works correctly
- [ ] Document access tracking and audit trails function properly
- [ ] Client feedback and approval workflows operate smoothly
- [ ] Mobile interface provides good user experience
- [ ] Security measures prevent unauthorized access
- [ ] All tests pass with >90% coverage
- [ ] Code review completed