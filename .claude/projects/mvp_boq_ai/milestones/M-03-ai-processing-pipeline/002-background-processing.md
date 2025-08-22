# Ticket 2: Background Processing Enhancement

**Epic**: M3 AI Processing & Extraction  
**Story Points**: 3  
**Dependencies**: 001-ai-service-integration.md

## Description
Enhance the existing AiProcessingJob to use the new AI service integration, add progress tracking, batch processing capabilities, and robust error handling. This creates a production-ready background processing system for AI specification analysis.

## Acceptance Criteria
- [ ] Enhanced AiProcessingJob with AI service integration
- [ ] Progress tracking and status updates via Turbo Streams
- [ ] Batch processing capabilities for multiple elements
- [ ] Comprehensive error handling and retry logic
- [ ] Processing metrics and monitoring
- [ ] Queue management and job priorities
- [ ] Webhook notifications for processing completion

## Code to be Written

### 1. Enhanced AI Processing Job
```ruby
# app/jobs/ai_processing_job.rb
class AiProcessingJob < ApplicationJob
  include JobErrorHandling
  include ProgressTracking
  
  queue_as :ai_processing
  
  retry_on Ai::ProcessingError, wait: :exponentially_longer, attempts: 5
  retry_on Net::TimeoutError, Errno::ECONNREFUSED, wait: 30.seconds, attempts: 3
  discard_on Ai::QuotaExceededError, Ai::ConfigurationError
  discard_on ActiveRecord::RecordNotFound

  before_perform :log_job_start
  after_perform :log_job_completion
  around_perform :track_processing_time

  def perform(element, options = {})
    return unless element.persisted? && element.specification.present?
    
    @element = element
    @options = options.with_indifferent_access
    @start_time = Time.current
    
    validate_element_state
    update_processing_status(:processing)
    
    begin
      result = process_with_ai_service
      handle_successful_processing(result)
      broadcast_completion
      
    rescue Ai::ProcessingError => e
      handle_processing_error(e)
      raise e if should_retry?(e)
      
    rescue => e
      handle_unexpected_error(e)
      raise e
    end
  end

  private

  def process_with_ai_service
    Rails.logger.info("Starting AI processing", {
      element_id: @element.id,
      project_id: @element.project.id,
      specification_length: @element.specification.length,
      options: @options
    })
    
    Ai::SpecificationProcessor.call(@element)
  end

  def handle_successful_processing(result)
    @element.transaction do
      @element.mark_as_processed!(
        extracted_params: result[:extracted_params],
        confidence_score: result[:confidence],
        element_type: result[:element_type],
        ai_notes: result[:notes]
      )
      
      record_processing_metrics(result)
      
      # Trigger next steps if confidence is high enough
      if result[:confidence] >= 0.8
        schedule_quantity_calculation
      end
    end
    
    Rails.logger.info("AI processing completed successfully", {
      element_id: @element.id,
      confidence: result[:confidence],
      element_type: result[:element_type],
      processing_time: processing_duration
    })
  end

  def handle_processing_error(error)
    @element.mark_as_failed!(error.message)
    
    Rails.logger.error("AI processing failed", {
      element_id: @element.id,
      error: error.message,
      error_class: error.class.name,
      processing_time: processing_duration,
      attempt: executions
    })
    
    broadcast_error(error)
    record_error_metrics(error)
  end

  def handle_unexpected_error(error)
    @element.mark_as_failed!("Unexpected error: #{error.message}")
    
    Rails.logger.error("Unexpected AI processing error", {
      element_id: @element.id,
      error: error.message,
      error_class: error.class.name,
      backtrace: error.backtrace&.first(5)
    })
    
    broadcast_error(error)
  end

  def validate_element_state
    unless @element.status.in?(%w[pending failed])
      raise ArgumentError, "Element #{@element.id} is not in a processable state: #{@element.status}"
    end
    
    if @element.specification.blank?
      raise ArgumentError, "Element #{@element.id} has no specification to process"
    end
  end

  def update_processing_status(status)
    case status
    when :processing
      @element.mark_as_processing!
      broadcast_status_update
    end
  end

  def should_retry?(error)
    return false if executions >= 5
    return false if error.is_a?(Ai::QuotaExceededError)
    return false if error.message.match?(/rate limit.*24 hour/i)
    
    true
  end

  def schedule_quantity_calculation
    return unless @options[:auto_calculate_quantities]
    
    QuantityCalculationJob.perform_later(@element)
  end

  def processing_duration
    return 0 unless @start_time
    ((Time.current - @start_time) * 1000).round
  end

  def broadcast_status_update
    broadcast_to_project(:replace, "element_#{@element.id}", "projects/elements/element_card")
  end

  def broadcast_completion
    broadcast_to_project(:replace, "element_#{@element.id}", "projects/elements/element_card")
    broadcast_notification(:success, "Element '#{@element.name}' processed successfully")
  end

  def broadcast_error(error)
    broadcast_to_project(:replace, "element_#{@element.id}", "projects/elements/element_card")
    broadcast_notification(:error, "Failed to process '#{@element.name}': #{error.message}")
  end

  def broadcast_to_project(action, target, partial)
    Turbo::StreamsChannel.broadcast_action_to(
      "project_#{@element.project.id}",
      action: action,
      target: target,
      partial: partial,
      locals: { element: @element.reload }
    )
  end

  def broadcast_notification(type, message)
    Turbo::StreamsChannel.broadcast_action_to(
      "project_#{@element.project.id}",
      action: :append,
      target: "notifications",
      partial: "shared/notification",
      locals: { type: type, message: message }
    )
  end

  def record_processing_metrics(result)
    ProcessingMetrics.record(
      element_id: @element.id,
      project_id: @element.project.id,
      processing_time: processing_duration,
      confidence_score: result[:confidence],
      element_type: result[:element_type],
      parameters_extracted: result[:extracted_params].keys.size,
      success: true
    )
  end

  def record_error_metrics(error)
    ProcessingMetrics.record(
      element_id: @element.id,
      project_id: @element.project.id,
      processing_time: processing_duration,
      error_type: error.class.name,
      error_message: error.message,
      success: false
    )
  end

  def log_job_start
    Rails.logger.info("AiProcessingJob started", {
      element_id: @element&.id,
      job_id: job_id,
      queue_name: queue_name,
      attempt: executions
    })
  end

  def log_job_completion
    Rails.logger.info("AiProcessingJob completed", {
      element_id: @element&.id,
      job_id: job_id,
      processing_time: processing_duration
    })
  end

  def track_processing_time
    start_time = Time.current
    yield
  ensure
    duration = ((Time.current - start_time) * 1000).round
    Rails.logger.info("Job processing time", {
      element_id: @element&.id,
      duration_ms: duration
    })
  end
end
```

### 2. Batch Processing Job
```ruby
# app/jobs/batch_ai_processing_job.rb
class BatchAiProcessingJob < ApplicationJob
  include JobErrorHandling
  
  queue_as :ai_processing
  
  def perform(project, options = {})
    @project = project
    @options = options.with_indifferent_access
    @batch_id = SecureRandom.uuid
    
    elements = find_processable_elements
    
    if elements.empty?
      Rails.logger.info("No elements to process", { project_id: @project.id })
      return
    end
    
    Rails.logger.info("Starting batch AI processing", {
      project_id: @project.id,
      batch_id: @batch_id,
      element_count: elements.count
    })
    
    batch_options = @options.merge(batch_id: @batch_id)
    
    elements.find_each do |element|
      AiProcessingJob.perform_later(element, batch_options)
    end
    
    broadcast_batch_started(elements.count)
  end

  private

  def find_processable_elements
    scope = @project.elements.needs_processing
    
    if @options[:element_ids].present?
      scope = scope.where(id: @options[:element_ids])
    end
    
    if @options[:element_types].present?
      scope = scope.where(element_type: @options[:element_types])
    end
    
    scope
  end

  def broadcast_batch_started(count)
    Turbo::StreamsChannel.broadcast_action_to(
      "project_#{@project.id}",
      action: :append,
      target: "notifications",
      partial: "shared/notification",
      locals: { 
        type: :info, 
        message: "Processing #{count} elements in background..." 
      }
    )
  end
end
```

### 3. Processing Metrics Model
```ruby
# app/models/processing_metrics.rb
class ProcessingMetrics < ApplicationRecord
  belongs_to :element, optional: true
  belongs_to :project, optional: true

  validates :processing_time, presence: true, numericality: { greater_than: 0 }
  validates :success, inclusion: { in: [true, false] }

  scope :successful, -> { where(success: true) }
  scope :failed, -> { where(success: false) }
  scope :for_project, ->(project) { where(project: project) }
  scope :recent, -> { where(created_at: 1.week.ago..) }

  class << self
    def record(attributes)
      create!(attributes.merge(recorded_at: Time.current))
    rescue => e
      Rails.logger.error("Failed to record processing metrics: #{e.message}")
    end

    def average_processing_time(scope = all)
      scope.successful.average(:processing_time) || 0
    end

    def success_rate(scope = all)
      total = scope.count
      return 0 if total.zero?
      
      successful = scope.successful.count
      (successful.to_f / total * 100).round(2)
    end

    def error_summary(scope = all)
      scope.failed
           .group(:error_type)
           .count
           .transform_keys { |k| k&.demodulize || "Unknown" }
    end
  end

  def duration_seconds
    processing_time / 1000.0
  end
end
```

### 4. Processing Metrics Migration
```ruby
# db/migrate/xxx_create_processing_metrics.rb
class CreateProcessingMetrics < ActiveRecord::Migration[8.0]
  def change
    create_table :processing_metrics do |t|
      t.references :element, null: true, foreign_key: true
      t.references :project, null: true, foreign_key: true
      t.integer :processing_time, null: false # milliseconds
      t.decimal :confidence_score, precision: 5, scale: 4
      t.string :element_type
      t.integer :parameters_extracted
      t.string :error_type
      t.text :error_message
      t.boolean :success, null: false, default: false
      t.datetime :recorded_at, null: false
      t.json :metadata, default: {}

      t.timestamps
    end

    add_index :processing_metrics, :project_id
    add_index :processing_metrics, :element_id
    add_index :processing_metrics, :success
    add_index :processing_metrics, :recorded_at
    add_index :processing_metrics, [:project_id, :success]
    add_index :processing_metrics, [:element_type, :success]
  end
end
```

### 5. Job Error Handling Concern
```ruby
# app/jobs/concerns/job_error_handling.rb
module JobErrorHandling
  extend ActiveSupport::Concern

  included do
    rescue_from StandardError do |error|
      handle_job_error(error)
      raise error
    end
  end

  private

  def handle_job_error(error)
    context = {
      job_class: self.class.name,
      job_id: job_id,
      queue_name: queue_name,
      arguments: arguments,
      executions: executions,
      error_class: error.class.name,
      error_message: error.message
    }

    case error
    when Ai::QuotaExceededError
      Rails.logger.warn("AI quota exceeded", context)
      schedule_retry_after_quota_reset
    when Ai::RateLimitError
      Rails.logger.warn("AI rate limit hit", context)
      # SolidQueue will handle retry with exponential backoff
    when Net::TimeoutError
      Rails.logger.warn("Network timeout", context)
    else
      Rails.logger.error("Job error", context.merge(backtrace: error.backtrace&.first(10)))
    end
  end

  def schedule_retry_after_quota_reset
    # Schedule retry for next day if quota is daily
    retry_at = Time.current.beginning_of_day + 1.day
    self.class.perform_at(retry_at, *arguments)
  end
end
```

### 6. Progress Tracking Concern
```ruby
# app/jobs/concerns/progress_tracking.rb
module ProgressTracking
  extend ActiveSupport::Concern

  def update_progress(current_step, total_steps, message = nil)
    progress_data = {
      current_step: current_step,
      total_steps: total_steps,
      percentage: ((current_step.to_f / total_steps) * 100).round(2),
      message: message,
      updated_at: Time.current
    }

    # Store progress in job metadata if supported
    if respond_to?(:job_metadata)
      job_metadata[:progress] = progress_data
    end

    # Broadcast progress update via Turbo Stream
    broadcast_progress_update(progress_data)
  end

  private

  def broadcast_progress_update(progress_data)
    return unless defined?(@element) && @element

    Turbo::StreamsChannel.broadcast_action_to(
      "project_#{@element.project.id}",
      action: :replace,
      target: "element_#{@element.id}_progress",
      partial: "shared/progress_bar",
      locals: { progress: progress_data }
    )
  end
end
```

### 7. Enhanced Controller Integration
```ruby
# Add to app/controllers/projects/elements_controller.rb

def bulk_process_advanced
  @elements = @project.elements.needs_processing
  authorize @elements, :update?
  
  options = {
    auto_calculate_quantities: params[:auto_calculate_quantities] == "true",
    element_types: params[:element_types]&.compact_blank,
    element_ids: params[:element_ids]&.compact_blank
  }
  
  BatchAiProcessingJob.perform_later(@project, options)
  
  respond_to do |format|
    format.html { redirect_to project_elements_path(@project), notice: "Batch processing started." }
    format.turbo_stream do
      flash.now[:notice] = "Batch processing started. You'll receive updates as elements are processed."
    end
  end
end

def processing_status
  @element = @project.elements.find(params[:id])
  authorize @element
  
  # Get latest processing metrics
  @metrics = ProcessingMetrics.where(element: @element).order(:created_at).last
  
  render json: {
    status: @element.status,
    confidence: @element.confidence_score,
    processed_at: @element.processed_at,
    processing_time: @metrics&.processing_time,
    success: @metrics&.success
  }
end
```

### 8. Job Tests
```ruby
# test/jobs/ai_processing_job_test.rb
require "test_helper"

class AiProcessingJobTest < ActiveJob::TestCase
  setup do
    @element = elements(:external_wall)
    @element.update!(status: 'pending')
  end

  test "should process element successfully" do
    assert_performed_with(job: AiProcessingJob, args: [@element]) do
      AiProcessingJob.perform_later(@element)
    end
    
    perform_enqueued_jobs
    
    @element.reload
    assert_equal 'processed', @element.status
    assert_not_nil @element.confidence_score
    assert_not_nil @element.extracted_params
  end

  test "should handle processing errors gracefully" do
    # Mock AI service to raise error
    Ai::SpecificationProcessor.stub(:call, -> { raise Ai::ProcessingError.new("Test error") }) do
      perform_enqueued_jobs do
        AiProcessingJob.perform_later(@element)
      end
    end
    
    @element.reload
    assert_equal 'failed', @element.status
    assert_includes @element.ai_notes, "Test error"
  end

  test "should retry on network errors" do
    attempt_count = 0
    
    Ai::SpecificationProcessor.stub(:call, -> {
      attempt_count += 1
      if attempt_count < 3
        raise Net::TimeoutError.new("Network timeout")
      else
        {
          element_type: "wall",
          confidence: 0.9,
          extracted_params: {},
          notes: "Success after retry"
        }
      end
    }) do
      perform_enqueued_jobs do
        AiProcessingJob.perform_later(@element)
      end
    end
    
    assert_equal 3, attempt_count
    assert_equal 'processed', @element.reload.status
  end

  test "should broadcast status updates" do
    assert_broadcasts("project_#{@element.project.id}", 2) do # processing + completion
      perform_enqueued_jobs do
        AiProcessingJob.perform_later(@element)
      end
    end
  end

  test "should record processing metrics" do
    assert_difference("ProcessingMetrics.count", 1) do
      perform_enqueued_jobs do
        AiProcessingJob.perform_later(@element)
      end
    end
    
    metric = ProcessingMetrics.last
    assert_equal @element, metric.element
    assert metric.success
    assert metric.processing_time > 0
  end
end
```

## Technical Notes
- Separates concerns with modules for error handling and progress tracking
- Uses database metrics for monitoring and analytics
- Implements intelligent retry logic based on error types
- Provides real-time status updates via Turbo Streams
- Supports batch processing for efficiency
- Includes comprehensive logging for debugging

## Definition of Done
- [ ] Enhanced job integrates with AI service successfully
- [ ] Progress tracking updates UI in real-time
- [ ] Batch processing handles multiple elements correctly
- [ ] Error handling covers all scenarios appropriately
- [ ] Metrics collection provides useful insights
- [ ] Retry logic functions as expected
- [ ] Real-time updates work via Turbo Streams
- [ ] Test coverage exceeds 95%
- [ ] Code review completed