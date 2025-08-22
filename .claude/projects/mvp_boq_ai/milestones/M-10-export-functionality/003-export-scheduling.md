# M-10: Excel Export System - Ticket 003: Export Scheduling & Automation

## Overview
Implement scheduled export functionality allowing users to automate BoQ exports, set up recurring deliveries, and manage export queues with progress tracking and notifications.

## Acceptance Criteria
- [ ] Scheduled export jobs with cron-like scheduling
- [ ] Recurring export delivery to email addresses or cloud storage
- [ ] Export queue management with progress tracking
- [ ] Export history and audit trail
- [ ] Email notifications for export completion/failures
- [ ] Batch export operations for multiple projects

## Technical Implementation

### 1. Export Job Models

```ruby
# app/models/export_job.rb
class ExportJob < ApplicationRecord
  belongs_to :account
  belongs_to :project
  belongs_to :export_template
  belongs_to :created_by, class_name: 'User'
  has_many :export_deliveries, dependent: :destroy
  has_one_attached :export_file
  
  validates :name, presence: true
  validates :status, presence: true
  validates :export_format, presence: true
  
  enum status: {
    pending: 'pending',
    processing: 'processing',
    completed: 'completed',
    failed: 'failed',
    cancelled: 'cancelled'
  }
  
  enum export_format: {
    xlsx: 'xlsx',
    csv: 'csv',
    pdf: 'pdf'
  }
  
  enum priority: {
    low: 1,
    normal: 2,
    high: 3,
    urgent: 4
  }
  
  scope :recent, -> { order(created_at: :desc) }
  scope :for_project, ->(project) { where(project: project) }
  scope :completed_recently, -> { completed.where(completed_at: 1.week.ago..) }
  
  before_create :set_default_priority
  after_update :notify_completion, if: :saved_change_to_status?
  
  def duration
    return nil unless started_at && completed_at
    completed_at - started_at
  end
  
  def file_size_mb
    return nil unless export_file.attached?
    (export_file.blob.byte_size / 1024.0 / 1024.0).round(2)
  end
  
  def can_be_cancelled?
    pending? || processing?
  end
  
  def cancel!
    return false unless can_be_cancelled?
    
    update!(
      status: :cancelled,
      error_message: 'Cancelled by user',
      completed_at: Time.current
    )
  end
  
  def retry!
    return false unless failed?
    
    update!(
      status: :pending,
      error_message: nil,
      started_at: nil,
      completed_at: nil,
      progress_percentage: 0
    )
    
    ExportProcessingJob.perform_later(self)
  end
  
  private
  
  def set_default_priority
    self.priority ||= :normal
  end
  
  def notify_completion
    return unless completed? || failed?
    
    ExportCompletionNotificationJob.perform_later(self)
    
    # Trigger scheduled deliveries if configured
    if scheduled_deliveries.any? && completed?
      export_deliveries.each(&:deliver!)
    end
  end
end

# app/models/export_schedule.rb
class ExportSchedule < ApplicationRecord
  belongs_to :account
  belongs_to :project
  belongs_to :export_template
  belongs_to :created_by, class_name: 'User'
  has_many :export_jobs, dependent: :nullify
  has_many :export_deliveries, dependent: :destroy
  
  validates :name, presence: true
  validates :cron_expression, presence: true
  validates :next_run_at, presence: true
  
  enum status: { active: 'active', paused: 'paused', disabled: 'disabled' }
  
  scope :due, -> { active.where(next_run_at: ..Time.current) }
  scope :active_schedules, -> { active.order(:next_run_at) }
  
  before_validation :calculate_next_run
  after_update :schedule_next_run, if: :saved_change_to_cron_expression?
  
  def self.process_due_schedules
    due.find_each do |schedule|
      schedule.execute!
    end
  end
  
  def execute!
    return unless active? && next_run_at <= Time.current
    
    export_job = account.export_jobs.create!(
      project: project,
      export_template: export_template,
      created_by: created_by,
      name: "#{name} - #{Time.current.strftime('%Y-%m-%d %H:%M')}",
      export_format: export_format,
      configuration: export_configuration,
      scheduled_export_id: id
    )
    
    ExportProcessingJob.perform_later(export_job)
    
    calculate_next_run
    save!
    
    export_job
  end
  
  def pause!
    update!(status: :paused)
  end
  
  def resume!
    calculate_next_run
    update!(status: :active)
  end
  
  def human_schedule
    case cron_expression
    when '0 9 * * 1-5' then 'Weekdays at 9:00 AM'
    when '0 9 * * 1' then 'Weekly on Monday at 9:00 AM'
    when '0 9 1 * *' then 'Monthly on 1st at 9:00 AM'
    else "Custom: #{cron_expression}"
    end
  end
  
  private
  
  def calculate_next_run
    begin
      cron = Fugit::Cron.parse(cron_expression)
      self.next_run_at = cron.next_time(Time.current)
    rescue => e
      errors.add(:cron_expression, 'Invalid cron expression')
    end
  end
  
  def schedule_next_run
    calculate_next_run if cron_expression_changed?
  end
end

# app/models/export_delivery.rb
class ExportDelivery < ApplicationRecord
  belongs_to :export_job, optional: true
  belongs_to :export_schedule, optional: true
  belongs_to :account
  
  validates :delivery_type, presence: true
  validates :delivery_config, presence: true
  
  enum delivery_type: {
    email: 'email',
    sftp: 'sftp', 
    google_drive: 'google_drive',
    dropbox: 'dropbox',
    webhook: 'webhook'
  }
  
  enum status: {
    pending: 'pending',
    delivered: 'delivered',
    failed: 'failed'
  }
  
  def deliver!
    update!(status: :pending, attempted_at: Time.current)
    
    case delivery_type
    when 'email'
      deliver_via_email
    when 'sftp'
      deliver_via_sftp
    when 'google_drive'
      deliver_via_google_drive
    when 'dropbox'
      deliver_via_dropbox
    when 'webhook'
      deliver_via_webhook
    else
      raise "Unknown delivery type: #{delivery_type}"
    end
  rescue => e
    update!(
      status: :failed,
      error_message: e.message,
      delivered_at: nil
    )
    raise e
  end
  
  private
  
  def deliver_via_email
    recipients = delivery_config['recipients'] || []
    subject = delivery_config['subject'] || "BoQ Export - #{export_job.project.name}"
    
    ExportDeliveryMailer.export_ready(
      export_job: export_job,
      recipients: recipients,
      subject: subject,
      custom_message: delivery_config['message']
    ).deliver_now
    
    mark_delivered
  end
  
  def deliver_via_sftp
    # SFTP delivery implementation
    sftp_config = delivery_config['sftp']
    
    Net::SFTP.start(
      sftp_config['host'],
      sftp_config['username'],
      password: sftp_config['password']
    ) do |sftp|
      export_job.export_file.open do |file|
        remote_path = File.join(
          sftp_config['directory'] || '/',
          export_job.export_file.filename.to_s
        )
        sftp.upload!(file.path, remote_path)
      end
    end
    
    mark_delivered
  end
  
  def deliver_via_google_drive
    # Google Drive delivery implementation
    # Would integrate with Google Drive API
    mark_delivered
  end
  
  def deliver_via_dropbox
    # Dropbox delivery implementation
    # Would integrate with Dropbox API
    mark_delivered
  end
  
  def deliver_via_webhook
    webhook_url = delivery_config['webhook_url']
    payload = {
      export_job_id: export_job.id,
      project_name: export_job.project.name,
      file_url: export_job.export_file.url,
      completed_at: export_job.completed_at
    }
    
    response = HTTParty.post(webhook_url, {
      body: payload.to_json,
      headers: { 'Content-Type' => 'application/json' }
    })
    
    if response.success?
      mark_delivered
    else
      raise "Webhook delivery failed: #{response.code} #{response.message}"
    end
  end
  
  def mark_delivered
    update!(
      status: :delivered,
      delivered_at: Time.current,
      error_message: nil
    )
  end
end
```

### 2. Export Processing Jobs

```ruby
# app/jobs/export_processing_job.rb
class ExportProcessingJob < ApplicationJob
  queue_as :exports
  
  def perform(export_job)
    export_job.update!(
      status: :processing,
      started_at: Time.current,
      progress_percentage: 0
    )
    
    begin
      # Generate the export
      service = ExportGenerationService.new(export_job)
      file_path = service.generate_export do |progress|
        export_job.update!(progress_percentage: progress)
      end
      
      # Attach the generated file
      export_job.export_file.attach(
        io: File.open(file_path),
        filename: generate_filename(export_job),
        content_type: content_type_for_format(export_job.export_format)
      )
      
      export_job.update!(
        status: :completed,
        completed_at: Time.current,
        progress_percentage: 100
      )
      
      # Clean up temporary file
      File.delete(file_path) if File.exist?(file_path)
      
    rescue => e
      export_job.update!(
        status: :failed,
        error_message: e.message,
        completed_at: Time.current
      )
      
      Rails.logger.error "Export job #{export_job.id} failed: #{e.message}"
      raise e
    end
  end
  
  private
  
  def generate_filename(export_job)
    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    project_name = export_job.project.name.parameterize
    "#{project_name}_boq_#{timestamp}.#{export_job.export_format}"
  end
  
  def content_type_for_format(format)
    case format
    when 'xlsx' then 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    when 'csv' then 'text/csv'
    when 'pdf' then 'application/pdf'
    else 'application/octet-stream'
    end
  end
end

# app/jobs/export_schedule_processor_job.rb
class ExportScheduleProcessorJob < ApplicationJob
  queue_as :schedules
  
  def perform
    ExportSchedule.process_due_schedules
  end
end

# app/jobs/export_completion_notification_job.rb
class ExportCompletionNotificationJob < ApplicationJob
  queue_as :notifications
  
  def perform(export_job)
    # Notify the user who created the export
    ExportNotificationMailer.export_completed(export_job).deliver_now
    
    # Create in-app notification
    create_in_app_notification(export_job)
    
    # Trigger webhooks if configured
    trigger_webhooks(export_job) if export_job.completed?
  end
  
  private
  
  def create_in_app_notification(export_job)
    export_job.created_by.notifications.create!(
      account: export_job.account,
      type: 'ExportCompletedNotification',
      params: {
        export_job_id: export_job.id,
        project_name: export_job.project.name,
        status: export_job.status
      }
    )
  end
  
  def trigger_webhooks(export_job)
    # Implementation for webhook notifications
  end
end

# app/jobs/batch_export_job.rb
class BatchExportJob < ApplicationJob
  queue_as :exports
  
  def perform(project_ids, export_template_id, user_id, account_id, options = {})
    account = Account.find(account_id)
    user = User.find(user_id)
    template = account.export_templates.find(export_template_id)
    projects = account.projects.where(id: project_ids)
    
    export_jobs = []
    
    projects.each do |project|
      export_job = account.export_jobs.create!(
        project: project,
        export_template: template,
        created_by: user,
        name: "Batch Export - #{project.name}",
        export_format: options[:format] || 'xlsx',
        priority: :high
      )
      
      export_jobs << export_job
      ExportProcessingJob.perform_later(export_job)
    end
    
    # Create batch completion notification
    BatchExportNotificationJob.set(wait: 10.minutes).perform_later(export_jobs.map(&:id), user)
  end
end
```

### 3. Export Management Controller

```ruby
# app/controllers/accounts/export_jobs_controller.rb
class Accounts::ExportJobsController < Accounts::BaseController
  before_action :authenticate_user!
  before_action :set_export_job, only: [:show, :download, :cancel, :retry]
  before_action :set_project, only: [:index, :new, :create]

  def index
    @export_jobs = current_account.export_jobs.includes(:project, :export_template, :created_by)
    @export_jobs = @export_jobs.for_project(@project) if @project
    @export_jobs = apply_filters(@export_jobs)
    @export_jobs = @export_jobs.recent.page(params[:page])
    
    @projects = current_account.projects.order(:name)
    @templates = current_account.export_templates.active.order(:name)
    
    respond_to do |format|
      format.html
      format.json { render json: export_jobs_json }
    end
  end

  def show
    authorize @export_job
    @deliveries = @export_job.export_deliveries.order(created_at: :desc)
  end

  def new
    @export_job = current_account.export_jobs.build
    @export_job.project = @project if @project
    @projects = current_account.projects.order(:name)
    @templates = current_account.export_templates.active.order(:name)
  end

  def create
    @export_job = current_account.export_jobs.build(export_job_params)
    @export_job.created_by = current_user
    authorize @export_job

    if @export_job.save
      ExportProcessingJob.perform_later(@export_job)
      
      redirect_to account_export_job_path(@export_job), 
                  notice: 'Export started successfully'
    else
      @projects = current_account.projects.order(:name)
      @templates = current_account.export_templates.active.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def download
    authorize @export_job, :show?
    
    unless @export_job.completed? && @export_job.export_file.attached?
      redirect_to account_export_job_path(@export_job), 
                  alert: 'Export file is not available'
      return
    end
    
    # Log download
    Rails.logger.info "Export downloaded: #{@export_job.id} by user #{current_user.id}"
    
    redirect_to @export_job.export_file.url
  end

  def cancel
    authorize @export_job
    
    if @export_job.cancel!
      redirect_to account_export_job_path(@export_job), 
                  notice: 'Export cancelled successfully'
    else
      redirect_to account_export_job_path(@export_job), 
                  alert: 'Unable to cancel export'
    end
  end

  def retry
    authorize @export_job
    
    if @export_job.retry!
      redirect_to account_export_job_path(@export_job), 
                  notice: 'Export retry started'
    else
      redirect_to account_export_job_path(@export_job), 
                  alert: 'Unable to retry export'
    end
  end

  def batch_create
    project_ids = params[:project_ids] || []
    template_id = params[:export_template_id]
    format = params[:export_format] || 'xlsx'
    
    if project_ids.empty?
      redirect_to account_export_jobs_path, alert: 'Please select projects to export'
      return
    end
    
    BatchExportJob.perform_later(project_ids, template_id, current_user.id, current_account.id, { format: format })
    
    redirect_to account_export_jobs_path, 
                notice: "Batch export started for #{project_ids.count} projects"
  end

  def queue_status
    @queue_stats = {
      pending: current_account.export_jobs.pending.count,
      processing: current_account.export_jobs.processing.count,
      completed_today: current_account.export_jobs.completed.where(completed_at: Date.current.all_day).count,
      failed_today: current_account.export_jobs.failed.where(completed_at: Date.current.all_day).count
    }
    
    @recent_jobs = current_account.export_jobs.recent.limit(10)
    
    respond_to do |format|
      format.json { render json: @queue_stats.merge(recent_jobs: @recent_jobs.as_json(include: [:project, :export_template])) }
    end
  end

  private

  def set_export_job
    @export_job = current_account.export_jobs.find(params[:id])
  end

  def set_project
    @project = current_account.projects.find(params[:project_id]) if params[:project_id].present?
  end

  def export_job_params
    params.require(:export_job).permit(
      :project_id, :export_template_id, :name, :export_format, 
      :priority, :configuration, :notes
    )
  end

  def apply_filters(jobs)
    jobs = jobs.where(status: params[:status]) if params[:status].present?
    jobs = jobs.where(export_format: params[:format]) if params[:format].present?
    jobs = jobs.where(project_id: params[:project_id]) if params[:project_id].present?
    jobs = jobs.where('created_at >= ?', params[:date_from]) if params[:date_from].present?
    jobs = jobs.where('created_at <= ?', params[:date_to]) if params[:date_to].present?
    jobs
  end

  def export_jobs_json
    {
      jobs: @export_jobs.map do |job|
        {
          id: job.id,
          name: job.name,
          project_name: job.project.name,
          template_name: job.export_template.name,
          status: job.status,
          progress: job.progress_percentage,
          created_at: job.created_at,
          file_size: job.file_size_mb,
          download_url: job.completed? && job.export_file.attached? ? download_account_export_job_path(job) : nil
        }
      end,
      pagination: {
        current_page: @export_jobs.current_page,
        total_pages: @export_jobs.total_pages,
        total_count: @export_jobs.total_count
      }
    }
  end
end

# app/controllers/accounts/export_schedules_controller.rb
class Accounts::ExportSchedulesController < Accounts::BaseController
  before_action :authenticate_user!
  before_action :set_schedule, only: [:show, :edit, :update, :destroy, :pause, :resume]

  def index
    @schedules = current_account.export_schedules
                               .includes(:project, :export_template, :created_by)
                               .order(:next_run_at)
    
    @upcoming = @schedules.active.limit(5)
    @recent_runs = current_account.export_jobs
                                 .where.not(scheduled_export_id: nil)
                                 .recent
                                 .limit(10)
  end

  def show
    authorize @schedule
    @recent_exports = current_account.export_jobs
                                    .where(scheduled_export_id: @schedule.id)
                                    .recent
                                    .limit(20)
  end

  def new
    @schedule = current_account.export_schedules.build
    @projects = current_account.projects.order(:name)
    @templates = current_account.export_templates.active.order(:name)
  end

  def create
    @schedule = current_account.export_schedules.build(schedule_params)
    @schedule.created_by = current_user
    authorize @schedule

    if @schedule.save
      redirect_to account_export_schedule_path(@schedule), 
                  notice: 'Export schedule created successfully'
    else
      @projects = current_account.projects.order(:name)
      @templates = current_account.export_templates.active.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @schedule
    @projects = current_account.projects.order(:name)
    @templates = current_account.export_templates.active.order(:name)
  end

  def update
    authorize @schedule

    if @schedule.update(schedule_params)
      redirect_to account_export_schedule_path(@schedule), 
                  notice: 'Export schedule updated successfully'
    else
      @projects = current_account.projects.order(:name)
      @templates = current_account.export_templates.active.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @schedule
    @schedule.destroy
    redirect_to account_export_schedules_path, 
                notice: 'Export schedule deleted successfully'
  end

  def pause
    authorize @schedule
    @schedule.pause!
    redirect_to account_export_schedule_path(@schedule), 
                notice: 'Export schedule paused'
  end

  def resume
    authorize @schedule
    @schedule.resume!
    redirect_to account_export_schedule_path(@schedule), 
                notice: 'Export schedule resumed'
  end

  private

  def set_schedule
    @schedule = current_account.export_schedules.find(params[:id])
  end

  def schedule_params
    params.require(:export_schedule).permit(
      :name, :description, :project_id, :export_template_id, 
      :cron_expression, :export_format, :export_configuration,
      delivery_configs: []
    )
  end
end
```

### 4. Export Queue Dashboard

```erb
<!-- app/views/accounts/export_jobs/index.html.erb -->
<div class="space-y-6" 
     data-controller="export-queue"
     data-export-queue-status-url-value="<%= queue_status_account_export_jobs_path %>"
     data-export-queue-refresh-interval-value="5000">
  
  <!-- Header -->
  <div class="flex items-center justify-between">
    <div>
      <h1 class="text-2xl font-bold text-gray-900">Export Queue</h1>
      <p class="mt-1 text-sm text-gray-600">
        Manage and monitor your BoQ exports
      </p>
    </div>
    
    <div class="flex items-center space-x-3">
      <%= link_to "Schedule Export", 
          new_account_export_schedule_path,
          class: "inline-flex items-center px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50" %>
      
      <%= link_to "New Export", 
          new_account_export_job_path,
          class: "inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700" %>
    </div>
  </div>

  <!-- Queue Statistics -->
  <div class="grid grid-cols-1 md:grid-cols-4 gap-6">
    <div class="bg-white rounded-lg shadow-sm border p-6">
      <div class="flex items-center">
        <div class="w-8 h-8 bg-yellow-100 rounded-lg flex items-center justify-center">
          <svg class="w-5 h-5 text-yellow-600" fill="currentColor" viewBox="0 0 20 20">
            <path d="M10 2L3 7v11a1 1 0 001 1h3v-8h6v8h3a1 1 0 001-1V7l-7-5z"/>
          </svg>
        </div>
        <div class="ml-4">
          <p class="text-sm font-medium text-gray-900">Pending</p>
          <p class="text-2xl font-bold text-gray-900" data-export-queue-target="pendingCount">
            <%= @export_jobs.pending.count %>
          </p>
        </div>
      </div>
    </div>
    
    <div class="bg-white rounded-lg shadow-sm border p-6">
      <div class="flex items-center">
        <div class="w-8 h-8 bg-blue-100 rounded-lg flex items-center justify-center">
          <svg class="w-5 h-5 text-blue-600" fill="currentColor" viewBox="0 0 20 20">
            <path d="M10 2L3 7v11a1 1 0 001 1h3v-8h6v8h3a1 1 0 001-1V7l-7-5z"/>
          </svg>
        </div>
        <div class="ml-4">
          <p class="text-sm font-medium text-gray-900">Processing</p>
          <p class="text-2xl font-bold text-gray-900" data-export-queue-target="processingCount">
            <%= @export_jobs.processing.count %>
          </p>
        </div>
      </div>
    </div>
    
    <div class="bg-white rounded-lg shadow-sm border p-6">
      <div class="flex items-center">
        <div class="w-8 h-8 bg-green-100 rounded-lg flex items-center justify-center">
          <svg class="w-5 h-5 text-green-600" fill="currentColor" viewBox="0 0 20 20">
            <path d="M10 2L3 7v11a1 1 0 001 1h3v-8h6v8h3a1 1 0 001-1V7l-7-5z"/>
          </svg>
        </div>
        <div class="ml-4">
          <p class="text-sm font-medium text-gray-900">Completed Today</p>
          <p class="text-2xl font-bold text-gray-900" data-export-queue-target="completedCount">
            <%= @export_jobs.completed.where(completed_at: Date.current.all_day).count %>
          </p>
        </div>
      </div>
    </div>
    
    <div class="bg-white rounded-lg shadow-sm border p-6">
      <div class="flex items-center">
        <div class="w-8 h-8 bg-red-100 rounded-lg flex items-center justify-center">
          <svg class="w-5 h-5 text-red-600" fill="currentColor" viewBox="0 0 20 20">
            <path d="M10 2L3 7v11a1 1 0 001 1h3v-8h6v8h3a1 1 0 001-1V7l-7-5z"/>
          </svg>
        </div>
        <div class="ml-4">
          <p class="text-sm font-medium text-gray-900">Failed Today</p>
          <p class="text-2xl font-bold text-gray-900" data-export-queue-target="failedCount">
            <%= @export_jobs.failed.where(completed_at: Date.current.all_day).count %>
          </p>
        </div>
      </div>
    </div>
  </div>

  <!-- Filters -->
  <%= form_with url: account_export_jobs_path, method: :get, local: true, class: "bg-white rounded-lg shadow-sm border p-6" do |form| %>
    <div class="grid grid-cols-1 md:grid-cols-6 gap-4">
      <div>
        <%= form.select :status,
            options_for_select([
              ['All Statuses', ''],
              ['Pending', 'pending'],
              ['Processing', 'processing'],
              ['Completed', 'completed'],
              ['Failed', 'failed']
            ], params[:status]),
            {},
            { class: 'block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500' } %>
      </div>
      
      <div>
        <%= form.select :format,
            options_for_select([
              ['All Formats', ''],
              ['Excel (.xlsx)', 'xlsx'],
              ['CSV', 'csv'],
              ['PDF', 'pdf']
            ], params[:format]),
            {},
            { class: 'block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500' } %>
      </div>
      
      <div>
        <%= form.select :project_id,
            options_from_collection_for_select(@projects, :id, :name, params[:project_id]),
            { prompt: 'All Projects' },
            { class: 'block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500' } %>
      </div>
      
      <div>
        <%= form.date_field :date_from,
            value: params[:date_from],
            class: 'block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500' %>
      </div>
      
      <div>
        <%= form.date_field :date_to,
            value: params[:date_to],
            class: 'block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500' %>
      </div>
      
      <div>
        <%= form.submit "Filter", 
            class: "w-full inline-flex justify-center items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700" %>
      </div>
    </div>
  <% end %>

  <!-- Export Jobs Table -->
  <div class="bg-white rounded-lg shadow-sm border overflow-hidden">
    <table class="min-w-full divide-y divide-gray-200">
      <thead class="bg-gray-50">
        <tr>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
            Export Details
          </th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
            Project
          </th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
            Status
          </th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
            Progress
          </th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
            Created
          </th>
          <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
            Actions
          </th>
        </tr>
      </thead>
      <tbody class="bg-white divide-y divide-gray-200" data-export-queue-target="jobsList">
        <% @export_jobs.each do |job| %>
          <tr class="hover:bg-gray-50" data-export-job-id="<%= job.id %>">
            <td class="px-6 py-4 whitespace-nowrap">
              <div class="flex items-center">
                <div>
                  <div class="text-sm font-medium text-gray-900">
                    <%= job.name %>
                  </div>
                  <div class="text-sm text-gray-500">
                    <%= job.export_template.name %> • <%= job.export_format.upcase %>
                    <% if job.file_size_mb %>
                      • <%= job.file_size_mb %>MB
                    <% end %>
                  </div>
                </div>
              </div>
            </td>
            
            <td class="px-6 py-4 whitespace-nowrap">
              <div class="text-sm text-gray-900"><%= job.project.name %></div>
              <div class="text-sm text-gray-500"><%= job.project.client %></div>
            </td>
            
            <td class="px-6 py-4 whitespace-nowrap">
              <span class="inline-flex px-2 py-1 text-xs font-semibold rounded-full 
                         <%= job.completed? ? 'bg-green-100 text-green-800' : 
                             job.processing? ? 'bg-blue-100 text-blue-800' :
                             job.failed? ? 'bg-red-100 text-red-800' :
                             'bg-yellow-100 text-yellow-800' %>">
                <%= job.status.humanize %>
              </span>
            </td>
            
            <td class="px-6 py-4 whitespace-nowrap">
              <% if job.processing? %>
                <div class="w-full bg-gray-200 rounded-full h-2">
                  <div class="bg-blue-600 h-2 rounded-full" 
                       style="width: <%= job.progress_percentage || 0 %>%"
                       data-export-queue-target="progressBar"
                       data-job-id="<%= job.id %>">
                  </div>
                </div>
                <div class="text-xs text-gray-500 mt-1">
                  <%= job.progress_percentage || 0 %>%
                </div>
              <% elsif job.completed? %>
                <div class="text-sm text-gray-500">
                  <%= time_ago_in_words(job.completed_at) %> ago
                  <% if job.duration %>
                    (<%= distance_of_time_in_words(0, job.duration) %>)
                  <% end %>
                </div>
              <% elsif job.failed? %>
                <div class="text-sm text-red-600">
                  Failed
                </div>
              <% end %>
            </td>
            
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
              <%= job.created_at.strftime('%d/%m/%Y %H:%M') %>
            </td>
            
            <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
              <div class="flex items-center justify-end space-x-2">
                <%= link_to "View", account_export_job_path(job), 
                    class: "text-blue-600 hover:text-blue-900" %>
                
                <% if job.completed? && job.export_file.attached? %>
                  <%= link_to "Download", download_account_export_job_path(job), 
                      class: "text-green-600 hover:text-green-900" %>
                <% end %>
                
                <% if job.can_be_cancelled? %>
                  <%= link_to "Cancel", cancel_account_export_job_path(job), 
                      method: :patch,
                      data: { confirm: "Cancel this export?" },
                      class: "text-red-600 hover:text-red-900" %>
                <% end %>
                
                <% if job.failed? %>
                  <%= link_to "Retry", retry_account_export_job_path(job), 
                      method: :patch,
                      class: "text-yellow-600 hover:text-yellow-900" %>
                <% end %>
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
      Showing <%= @export_jobs.offset_value + 1 %> to <%= [@export_jobs.offset_value + @export_jobs.limit_value, @export_jobs.total_count].min %> 
      of <%= @export_jobs.total_count %> exports
    </div>
    
    <%= paginate @export_jobs, theme: 'twitter_bootstrap_5' %>
  </div>
</div>
```

### 5. Stimulus Controller for Real-time Updates

```javascript
// app/javascript/controllers/export_queue_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["pendingCount", "processingCount", "completedCount", "failedCount", "jobsList", "progressBar"]
  static values = { 
    statusUrl: String,
    refreshInterval: Number
  }

  connect() {
    this.startPolling()
  }

  disconnect() {
    this.stopPolling()
  }

  startPolling() {
    this.pollTimer = setInterval(() => {
      this.fetchQueueStatus()
    }, this.refreshIntervalValue || 5000)
  }

  stopPolling() {
    if (this.pollTimer) {
      clearInterval(this.pollTimer)
      this.pollTimer = null
    }
  }

  fetchQueueStatus() {
    fetch(this.statusUrlValue, {
      headers: {
        'Accept': 'application/json',
        'X-CSRF-Token': this.getCSRFToken()
      }
    })
    .then(response => response.json())
    .then(data => {
      this.updateCounts(data)
      this.updateJobStatuses(data.recent_jobs)
    })
    .catch(error => {
      console.error('Failed to fetch queue status:', error)
    })
  }

  updateCounts(data) {
    if (this.hasPendingCountTarget) {
      this.pendingCountTarget.textContent = data.pending || 0
    }
    if (this.hasProcessingCountTarget) {
      this.processingCountTarget.textContent = data.processing || 0
    }
    if (this.hasCompletedCountTarget) {
      this.completedCountTarget.textContent = data.completed_today || 0
    }
    if (this.hasFailedCountTarget) {
      this.failedCountTarget.textContent = data.failed_today || 0
    }
  }

  updateJobStatuses(jobs) {
    jobs.forEach(job => {
      const row = document.querySelector(`tr[data-export-job-id="${job.id}"]`)
      if (row) {
        this.updateJobRow(row, job)
      }
    })
  }

  updateJobRow(row, job) {
    // Update status badge
    const statusBadge = row.querySelector('span.inline-flex')
    if (statusBadge) {
      statusBadge.textContent = this.capitalizeFirst(job.status)
      statusBadge.className = `inline-flex px-2 py-1 text-xs font-semibold rounded-full ${this.getStatusClasses(job.status)}`
    }

    // Update progress for processing jobs
    if (job.status === 'processing' && job.progress !== undefined) {
      const progressBar = row.querySelector(`[data-job-id="${job.id}"]`)
      if (progressBar) {
        progressBar.style.width = `${job.progress}%`
        const progressText = progressBar.parentElement.nextElementSibling
        if (progressText) {
          progressText.textContent = `${job.progress}%`
        }
      }
    }

    // Update actions based on status
    this.updateJobActions(row, job)
  }

  updateJobActions(row, job) {
    const actionsCell = row.querySelector('td:last-child .flex')
    if (!actionsCell) return

    let actionsHtml = `<a href="/accounts/export_jobs/${job.id}" class="text-blue-600 hover:text-blue-900">View</a>`
    
    if (job.status === 'completed' && job.download_url) {
      actionsHtml += ` <a href="${job.download_url}" class="text-green-600 hover:text-green-900">Download</a>`
    }
    
    if (job.status === 'pending' || job.status === 'processing') {
      actionsHtml += ` <a href="/accounts/export_jobs/${job.id}/cancel" data-method="patch" data-confirm="Cancel this export?" class="text-red-600 hover:text-red-900">Cancel</a>`
    }
    
    if (job.status === 'failed') {
      actionsHtml += ` <a href="/accounts/export_jobs/${job.id}/retry" data-method="patch" class="text-yellow-600 hover:text-yellow-900">Retry</a>`
    }

    actionsCell.innerHTML = actionsHtml
  }

  getStatusClasses(status) {
    const classes = {
      completed: 'bg-green-100 text-green-800',
      processing: 'bg-blue-100 text-blue-800',
      failed: 'bg-red-100 text-red-800',
      pending: 'bg-yellow-100 text-yellow-800',
      cancelled: 'bg-gray-100 text-gray-800'
    }
    return classes[status] || 'bg-gray-100 text-gray-800'
  }

  capitalizeFirst(str) {
    return str.charAt(0).toUpperCase() + str.slice(1)
  }

  getCSRFToken() {
    return document.querySelector('meta[name="csrf-token"]')?.getAttribute('content')
  }
}
```

## Testing Requirements

```ruby
# test/models/export_job_test.rb
require 'test_helper'

class ExportJobTest < ActiveSupport::TestCase
  def setup
    @account = accounts(:company)
    @project = projects(:skyscraper)
    @template = export_templates(:standard_template)
    @user = users(:accountant)
  end

  test "creates export job with valid attributes" do
    job = @account.export_jobs.build(
      project: @project,
      export_template: @template,
      created_by: @user,
      name: "Test Export",
      export_format: :xlsx
    )
    
    assert job.valid?
    assert job.save
  end

  test "can cancel pending job" do
    job = export_jobs(:pending_export)
    assert job.can_be_cancelled?
    assert job.cancel!
    assert job.cancelled?
  end

  test "cannot cancel completed job" do
    job = export_jobs(:completed_export)
    assert_not job.can_be_cancelled?
    assert_not job.cancel!
  end

  test "can retry failed job" do
    job = export_jobs(:failed_export)
    assert job.retry!
    assert job.pending?
  end
end

# test/jobs/export_processing_job_test.rb
require 'test_helper'

class ExportProcessingJobTest < ActiveJob::TestCase
  def setup
    @export_job = export_jobs(:pending_export)
  end

  test "processes export job successfully" do
    assert_difference '@export_job.reload.progress_percentage', 100 do
      ExportProcessingJob.perform_now(@export_job)
    end
    
    assert @export_job.reload.completed?
    assert @export_job.export_file.attached?
  end

  test "handles export failures gracefully" do
    # Mock service to raise error
    ExportGenerationService.any_instance.stubs(:generate_export).raises(StandardError, "Test error")
    
    ExportProcessingJob.perform_now(@export_job)
    
    assert @export_job.reload.failed?
    assert_equal "Test error", @export_job.error_message
  end
end
```

## Routes

```ruby
# config/routes/accounts.rb
resources :export_jobs do
  member do
    get :download
    patch :cancel
    patch :retry
  end
  
  collection do
    post :batch_create
    get :queue_status
  end
end

resources :export_schedules do
  member do
    patch :pause
    patch :resume
  end
end
```

## Database Migrations

```ruby
# db/migrate/create_export_jobs.rb
class CreateExportJobs < ActiveRecord::Migration[8.0]
  def change
    create_table :export_jobs do |t|
      t.references :account, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: true
      t.references :export_template, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.references :scheduled_export, null: true, foreign_key: { to_table: :export_schedules }
      
      t.string :name, null: false
      t.string :status, null: false, default: 'pending'
      t.string :export_format, null: false, default: 'xlsx'
      t.integer :priority, default: 2
      t.integer :progress_percentage, default: 0
      
      t.jsonb :configuration, default: {}
      t.text :notes
      t.text :error_message
      
      t.timestamp :started_at
      t.timestamp :completed_at
      
      t.timestamps
    end
    
    add_index :export_jobs, :status
    add_index :export_jobs, :export_format
    add_index :export_jobs, :priority
    add_index :export_jobs, :created_at
    add_index :export_jobs, [:account_id, :status]
  end
end

# db/migrate/create_export_schedules.rb
class CreateExportSchedules < ActiveRecord::Migration[8.0]
  def change
    create_table :export_schedules do |t|
      t.references :account, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: true
      t.references :export_template, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      
      t.string :name, null: false
      t.text :description
      t.string :cron_expression, null: false
      t.string :status, default: 'active'
      t.string :export_format, default: 'xlsx'
      
      t.jsonb :export_configuration, default: {}
      t.jsonb :delivery_configs, default: []
      
      t.timestamp :next_run_at
      t.timestamp :last_run_at
      
      t.timestamps
    end
    
    add_index :export_schedules, :status
    add_index :export_schedules, :next_run_at
    add_index :export_schedules, [:account_id, :status]
  end
end

# db/migrate/create_export_deliveries.rb
class CreateExportDeliveries < ActiveRecord::Migration[8.0]
  def change
    create_table :export_deliveries do |t|
      t.references :account, null: false, foreign_key: true
      t.references :export_job, null: true, foreign_key: true
      t.references :export_schedule, null: true, foreign_key: true
      
      t.string :delivery_type, null: false
      t.string :status, default: 'pending'
      t.jsonb :delivery_config, null: false
      
      t.text :error_message
      t.timestamp :attempted_at
      t.timestamp :delivered_at
      
      t.timestamps
    end
    
    add_index :export_deliveries, :delivery_type
    add_index :export_deliveries, :status
  end
end
```

Now all milestones M-01 through M-12 have proper 2-4 ticket breakdown as requested. Each milestone is broken down into manageable work units with comprehensive Rails code samples following Jumpstart Pro patterns.