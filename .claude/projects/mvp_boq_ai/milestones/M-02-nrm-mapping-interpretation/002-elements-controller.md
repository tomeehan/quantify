# Ticket 2: Create Elements Controller

**Epic**: M2 Specification Input  
**Story Points**: 4  
**Dependencies**: 001-element-model.md

## Description
Create the Elements controller that handles CRUD operations for building specifications within projects. Controller should be nested under projects, follow Jumpstart Pro patterns for account-scoped resources, and support bulk operations for specification processing.

## Acceptance Criteria
- [ ] Nested elements controller under projects
- [ ] Full CRUD operations with account scoping
- [ ] Bulk operations for processing multiple elements
- [ ] Hotwire-compatible responses for smooth UX
- [ ] Proper error handling and validation display
- [ ] Background job integration for AI processing
- [ ] Pundit authorization for all actions

## Code to be Written

### 1. Elements Controller
```ruby
# app/controllers/projects/elements_controller.rb
class Projects::ElementsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_project
  before_action :set_element, only: [:show, :edit, :update, :destroy, :process, :verify]

  def index
    @elements = @project.elements.includes(:quantities, :assemblies).recent
    authorize @elements
    
    @pending_count = @elements.by_status('pending').count
    @processing_count = @elements.by_status('processing').count
    @processed_count = @elements.processed.count
  end

  def show
    authorize @element
    @quantities = @element.quantities.includes(:assembly, :boq_lines)
    @missing_params = @element.missing_params
  end

  def new
    @element = @project.elements.build
    authorize @element
  end

  def create
    @element = @project.elements.build(element_params)
    authorize @element

    if @element.save
      # Queue for AI processing if specification is provided
      AiProcessingJob.perform_later(@element) if @element.specification.present?
      
      respond_to do |format|
        format.html { redirect_to [@project, @element], notice: "Element was successfully created." }
        format.turbo_stream do
          flash.now[:notice] = "Element created and queued for processing."
        end
      end
    else
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "element_form", 
            partial: "form", 
            locals: { project: @project, element: @element }
          )
        end
      end
    end
  end

  def edit
    authorize @element
  end

  def update
    authorize @element
    old_specification = @element.specification

    if @element.update(element_params)
      # Re-queue for processing if specification changed
      if @element.specification != old_specification && @element.specification.present?
        @element.update!(status: 'pending')
        AiProcessingJob.perform_later(@element)
      end

      respond_to do |format|
        format.html { redirect_to [@project, @element], notice: "Element was successfully updated." }
        format.turbo_stream do
          flash.now[:notice] = "Element updated successfully."
        end
      end
    else
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "element_form",
            partial: "form",
            locals: { project: @project, element: @element }
          )
        end
      end
    end
  end

  def destroy
    authorize @element
    @element.destroy

    respond_to do |format|
      format.html { redirect_to project_elements_path(@project), notice: "Element was successfully deleted." }
      format.turbo_stream do
        flash.now[:notice] = "Element deleted successfully."
      end
    end
  end

  def process
    authorize @element, :update?
    
    if @element.status == 'pending' || @element.status == 'failed'
      @element.mark_as_processing!
      AiProcessingJob.perform_later(@element)
      
      respond_to do |format|
        format.html { redirect_to [@project, @element], notice: "Element queued for processing." }
        format.turbo_stream do
          flash.now[:notice] = "Processing started..."
        end
      end
    else
      respond_to do |format|
        format.html { redirect_to [@project, @element], alert: "Element cannot be processed in current state." }
        format.turbo_stream do
          flash.now[:alert] = "Element cannot be processed in current state."
        end
      end
    end
  end

  def verify
    authorize @element, :update?
    
    if @element.status == 'processed'
      @element.mark_as_verified!
      
      respond_to do |format|
        format.html { redirect_to [@project, @element], notice: "Element verified successfully." }
        format.turbo_stream do
          flash.now[:notice] = "Element verified."
        end
      end
    else
      respond_to do |format|
        format.html { redirect_to [@project, @element], alert: "Element is not ready for verification." }
        format.turbo_stream do
          flash.now[:alert] = "Element is not ready for verification."
        end
      end
    end
  end

  def bulk_process
    @elements = @project.elements.needs_processing
    authorize @elements, :update?
    
    processed_count = 0
    @elements.each do |element|
      if element.status.in?(['pending', 'failed'])
        element.mark_as_processing!
        AiProcessingJob.perform_later(element)
        processed_count += 1
      end
    end

    respond_to do |format|
      format.html { redirect_to project_elements_path(@project), notice: "#{processed_count} elements queued for processing." }
      format.turbo_stream do
        flash.now[:notice] = "#{processed_count} elements queued for processing."
      end
    end
  end

  def update_params
    authorize @element, :update?
    
    if params[:user_params].present?
      current_params = @element.user_params || {}
      updated_params = current_params.merge(params[:user_params].permit!)
      
      if @element.update(user_params: updated_params)
        respond_to do |format|
          format.html { redirect_to [@project, @element], notice: "Parameters updated successfully." }
          format.turbo_stream do
            render turbo_stream: [
              turbo_stream.replace("element_params", partial: "shared/element_params", locals: { element: @element }),
              turbo_stream.prepend("flash", partial: "shared/flash", locals: { notice: "Parameters updated" })
            ]
          end
        end
      else
        respond_to do |format|
          format.html { redirect_to [@project, @element], alert: "Failed to update parameters." }
          format.turbo_stream do
            flash.now[:alert] = "Failed to update parameters."
          end
        end
      end
    else
      redirect_to [@project, @element], alert: "No parameters provided."
    end
  end

  private

  def set_project
    @project = current_account.projects.find(params[:project_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to projects_path, alert: "Project not found."
  end

  def set_element
    @element = @project.elements.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to project_elements_path(@project), alert: "Element not found."
  end

  def element_params
    params.require(:element).permit(:name, :specification, :element_type, user_params: {})
  end
end
```

### 2. Pundit Policy
```ruby
# app/policies/element_policy.rb
class ElementPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.admin?
        scope.all
      else
        scope.joins(project: :account).where(projects: { accounts: { id: user.account_ids } })
      end
    end
  end

  def index?
    user.present? && user_can_access_project?
  end

  def show?
    user_can_access_element?
  end

  def new?
    user.present? && user_can_access_project?
  end

  def create?
    user.present? && user_can_access_project?
  end

  def edit?
    user_can_access_element?
  end

  def update?
    user_can_access_element?
  end

  def destroy?
    user_can_access_element? && (user.admin? || user_is_account_owner?)
  end

  def process?
    user_can_access_element?
  end

  def verify?
    user_can_access_element?
  end

  def bulk_process?
    user.present? && user_can_access_project?
  end

  def update_params?
    user_can_access_element?
  end

  private

  def user_can_access_element?
    user.present? && 
    record.present? && 
    user.account_ids.include?(record.project.account_id)
  end

  def user_can_access_project?
    user.present? && 
    record.respond_to?(:project) && 
    user.account_ids.include?(record.project.account_id)
  end

  def user_is_account_owner?
    return false unless record.respond_to?(:project)
    user.account_users.find_by(account: record.project.account)&.owner?
  end
end
```

### 3. Routes Configuration
```ruby
# Add to config/routes.rb within existing structure
Rails.application.routes.draw do
  # ... existing routes

  resources :projects do
    resources :elements do
      member do
        patch :process
        patch :verify
        patch :update_params
      end
      
      collection do
        patch :bulk_process
      end
    end
  end

  # ... rest of routes
end
```

### 4. Background Job for AI Processing
```ruby
# app/jobs/ai_processing_job.rb
class AiProcessingJob < ApplicationJob
  queue_as :default
  
  retry_on StandardError, wait: :exponentially_longer, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  def perform(element)
    return unless element.persisted?
    
    Rails.logger.info "Starting AI processing for Element #{element.id}"
    
    begin
      # Mark as processing
      element.mark_as_processing!
      
      # Call AI service (placeholder for actual implementation)
      result = AiSpecificationProcessor.new(element).process
      
      # Update element with results
      element.mark_as_processed!(
        extracted_params: result[:parameters],
        confidence_score: result[:confidence],
        element_type: result[:element_type],
        ai_notes: result[:notes]
      )
      
      Rails.logger.info "AI processing completed for Element #{element.id} with confidence #{result[:confidence]}"
      
      # Broadcast update via Turbo Stream
      broadcast_element_update(element)
      
    rescue => e
      Rails.logger.error "AI processing failed for Element #{element.id}: #{e.message}"
      element.mark_as_failed!(e.message)
      
      # Broadcast failure
      broadcast_element_update(element)
      
      raise e
    end
  end

  private

  def broadcast_element_update(element)
    # Broadcast to project channel for real-time updates
    Turbo::StreamsChannel.broadcast_replace_to(
      "project_#{element.project.id}",
      target: "element_#{element.id}",
      partial: "projects/elements/element_card",
      locals: { element: element }
    )
  end
end
```

### 5. Controller Tests
```ruby
# test/controllers/projects/elements_controller_test.rb
require "test_helper"

class Projects::ElementsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:company)
    @user = users(:one)
    @user.account_users.create!(account: @account, role: :owner)
    sign_in @user
    switch_account(@account)
    
    @project = projects(:office_building)
    @element = elements(:external_wall)
  end

  test "should get index" do
    get project_elements_url(@project)
    assert_response :success
    assert_select "h1", "Elements"
  end

  test "should get new" do
    get new_project_element_url(@project)
    assert_response :success
    assert_select "form"
  end

  test "should create element" do
    assert_difference("Element.count") do
      post project_elements_url(@project), params: {
        element: {
          name: "New Wall",
          specification: "Test specification for new wall element"
        }
      }
    end

    assert_redirected_to project_element_url(@project, Element.last)
    assert_equal "Element was successfully created.", flash[:notice]
  end

  test "should show element" do
    get project_element_url(@project, @element)
    assert_response :success
    assert_select "h1", @element.name
  end

  test "should get edit" do
    get edit_project_element_url(@project, @element)
    assert_response :success
    assert_select "form"
  end

  test "should update element" do
    patch project_element_url(@project, @element), params: {
      element: { name: "Updated Wall Name" }
    }
    assert_redirected_to project_element_url(@project, @element)
    assert_equal "Updated Wall Name", @element.reload.name
  end

  test "should destroy element" do
    assert_difference("Element.count", -1) do
      delete project_element_url(@project, @element)
    end
    assert_redirected_to project_elements_url(@project)
  end

  test "should process element" do
    @element.update!(status: 'pending')
    
    assert_enqueued_with(job: AiProcessingJob, args: [@element]) do
      patch process_project_element_url(@project, @element)
    end
    
    assert_equal 'processing', @element.reload.status
    assert_redirected_to project_element_url(@project, @element)
  end

  test "should verify element" do
    @element.update!(status: 'processed')
    
    patch verify_project_element_url(@project, @element)
    
    assert_equal 'verified', @element.reload.status
    assert_redirected_to project_element_url(@project, @element)
  end

  test "should bulk process elements" do
    pending_element = @project.elements.create!(
      name: "Pending Element",
      specification: "Another specification",
      status: 'pending'
    )
    
    assert_enqueued_jobs 1, only: AiProcessingJob do
      patch bulk_process_project_elements_url(@project)
    end
    
    assert_redirected_to project_elements_url(@project)
  end

  test "should update element parameters" do
    patch update_params_project_element_url(@project, @element), params: {
      user_params: { width: 100, height: 200 }
    }
    
    @element.reload
    assert_equal 100, @element.user_params["width"]
    assert_equal 200, @element.user_params["height"]
    assert_redirected_to project_element_url(@project, @element)
  end

  test "should not access element from different account" do
    other_account = accounts(:personal)
    other_project = Project.create!(
      account: other_account,
      client: "Other Client",
      title: "Other Project",
      address: "123 Other St",
      region: "Other Region"
    )
    other_element = Element.create!(
      project: other_project,
      name: "Other Element",
      specification: "Other specification"
    )
    
    get project_element_url(other_project, other_element)
    assert_redirected_to projects_path
    assert_equal "Project not found.", flash[:alert]
  end
end
```

## Technical Notes
- Nested under projects for proper REST hierarchy
- Uses Turbo Streams for real-time updates during processing
- Background jobs handle AI processing to avoid blocking UI
- Bulk operations improve UX for multiple elements
- Parameter updates use JSON merging to preserve existing data
- Proper error handling for RecordNotFound scenarios

## Definition of Done
- [ ] Controller passes all tests
- [ ] Pundit policies implemented and tested
- [ ] Routes configured correctly
- [ ] Background job integration working
- [ ] Hotwire responses function correctly
- [ ] Bulk operations work properly
- [ ] Error handling covers edge cases
- [ ] Code review completed