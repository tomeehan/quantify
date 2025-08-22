# Ticket 2: Interactive Q&A Interface

**Epic**: M6 Question Resolution  
**Story Points**: 5  
**Dependencies**: 001-dynamic-forms.md

## Description
Create an interactive question-and-answer interface that guides users through parameter collection with context-aware questions, progressive disclosure, and intelligent skip logic based on previous answers.

## Acceptance Criteria
- [ ] Step-by-step Q&A workflow with progress tracking
- [ ] Context-aware questions based on element type and NRM code
- [ ] Progressive disclosure that shows only relevant questions
- [ ] Skip logic that adapts based on previous answers
- [ ] Real-time validation with helpful error messages
- [ ] Save and resume functionality for long question sequences
- [ ] Mobile-optimized question interface

## Code to be Written

### 1. Q&A Session Controller
```ruby
# app/controllers/qa_sessions_controller.rb
class QaSessionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_element
  before_action :set_qa_session

  def show
    authorize @qa_session
    
    @current_question = @qa_session.current_question
    @progress = @qa_session.progress_percentage
    @answered_questions = @qa_session.answered_questions
  end

  def answer_question
    authorize @qa_session
    
    question_id = params[:question_id]
    answer_data = params[:answer_data]
    
    result = @qa_session.answer_question(question_id, answer_data)
    
    if result[:success]
      @qa_session.advance_to_next_question
      
      respond_to do |format|
        format.json { 
          render json: {
            success: true,
            next_question: @qa_session.current_question&.to_hash,
            progress: @qa_session.progress_percentage,
            is_complete: @qa_session.complete?
          }
        }
        format.turbo_stream {
          if @qa_session.complete?
            render turbo_stream: turbo_stream.replace("qa-container", 
                                                     partial: "completion_summary", 
                                                     locals: { qa_session: @qa_session })
          else
            render turbo_stream: turbo_stream.replace("current-question", 
                                                     partial: "question_form", 
                                                     locals: { question: @qa_session.current_question })
          end
        }
      end
    else
      respond_to do |format|
        format.json { render json: { success: false, errors: result[:errors] } }
        format.turbo_stream {
          render turbo_stream: turbo_stream.update("question-errors", 
                                                   partial: "question_errors", 
                                                   locals: { errors: result[:errors] })
        }
      end
    end
  end

  def skip_question
    authorize @qa_session
    
    question_id = params[:question_id]
    skip_reason = params[:skip_reason]
    
    @qa_session.skip_question(question_id, skip_reason)
    @qa_session.advance_to_next_question
    
    respond_to do |format|
      format.json { 
        render json: {
          success: true,
          next_question: @qa_session.current_question&.to_hash,
          progress: @qa_session.progress_percentage,
          is_complete: @qa_session.complete?
        }
      }
      format.turbo_stream {
        if @qa_session.complete?
          render turbo_stream: turbo_stream.replace("qa-container", 
                                                   partial: "completion_summary", 
                                                   locals: { qa_session: @qa_session })
        else
          render turbo_stream: turbo_stream.replace("current-question", 
                                                   partial: "question_form", 
                                                   locals: { question: @qa_session.current_question })
        end
      }
    end
  end

  def go_back
    authorize @qa_session
    
    @qa_session.go_to_previous_question
    
    respond_to do |format|
      format.json { 
        render json: {
          success: true,
          question: @qa_session.current_question&.to_hash,
          progress: @qa_session.progress_percentage
        }
      }
      format.turbo_stream {
        render turbo_stream: turbo_stream.replace("current-question", 
                                                 partial: "question_form", 
                                                 locals: { question: @qa_session.current_question })
      }
    end
  end

  def complete_session
    authorize @qa_session
    
    if @qa_session.finalize!
      # Apply collected parameters to element
      @element.update!(
        clarification_parameters: @qa_session.collected_parameters,
        clarification_status: "completed",
        clarification_completed_at: Time.current
      )
      
      # Trigger next workflow step (quantity calculation)
      ElementQuantityCalculationJob.perform_later(@element)
      
      redirect_to project_element_path(@element.project, @element), 
                  notice: "Parameter collection completed successfully!"
    else
      render :show, alert: "Unable to complete session. Please check your answers."
    end
  end

  def save_and_resume_later
    authorize @qa_session
    
    @qa_session.mark_as_paused!
    
    respond_to do |format|
      format.json { render json: { success: true, message: "Progress saved" } }
      format.html { 
        redirect_to project_element_path(@element.project, @element), 
                    notice: "Progress saved. You can resume later."
      }
    end
  end

  private

  def set_element
    @element = current_account.projects.joins(:elements).find(params[:element_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to projects_path, alert: "Element not found."
  end

  def set_qa_session
    @qa_session = @element.qa_sessions.find_or_create_by(
      user: current_user,
      status: ["active", "paused"]
    ) do |session|
      session.initialize_questions!
    end
  end
end
```

### 2. Q&A Session Model
```ruby
# app/models/qa_session.rb
class QaSession < ApplicationRecord
  belongs_to :element
  belongs_to :user
  has_many :qa_answers, dependent: :destroy

  validates :status, presence: true
  validates :question_sequence, presence: true

  enum status: { active: 0, paused: 1, completed: 2, abandoned: 3 }

  serialize :question_sequence, Array
  serialize :collected_parameters, Hash

  def initialize_questions!
    generator = QuestionSequenceGenerator.new(element)
    self.question_sequence = generator.generate_sequence
    self.current_question_index = 0
    self.collected_parameters = {}
    save!
  end

  def current_question
    return nil if current_question_index >= question_sequence.length
    
    question_data = question_sequence[current_question_index]
    Question.new(question_data)
  end

  def progress_percentage
    return 100 if complete?
    return 0 if question_sequence.empty?
    
    ((current_question_index.to_f / question_sequence.length) * 100).round(1)
  end

  def answered_questions
    qa_answers.includes(:question_data).order(:created_at)
  end

  def answer_question(question_id, answer_data)
    question = current_question
    return { success: false, errors: ["No current question"] } unless question
    return { success: false, errors: ["Question ID mismatch"] } unless question.id == question_id

    # Validate answer
    validation_result = question.validate_answer(answer_data)
    unless validation_result[:valid]
      return { success: false, errors: validation_result[:errors] }
    end

    # Save answer
    qa_answer = qa_answers.create!(
      question_id: question_id,
      question_data: question.to_hash,
      answer_data: answer_data,
      answered_at: Time.current
    )

    # Update collected parameters
    parameter_key = question.parameter_key
    if parameter_key
      collected_parameters[parameter_key] = answer_data["value"]
      save!
    end

    # Check if this answer affects future questions (skip logic)
    update_question_sequence_based_on_answer(question, answer_data)

    { success: true, answer: qa_answer }
  end

  def skip_question(question_id, reason)
    question = current_question
    return false unless question && question.id == question_id

    qa_answers.create!(
      question_id: question_id,
      question_data: question.to_hash,
      answer_data: { "skipped" => true, "skip_reason" => reason },
      answered_at: Time.current
    )

    true
  end

  def advance_to_next_question
    self.current_question_index += 1
    
    if current_question_index >= question_sequence.length
      mark_as_completed!
    else
      save!
    end
  end

  def go_to_previous_question
    if current_question_index > 0
      self.current_question_index -= 1
      save!
    end
  end

  def complete?
    completed? || current_question_index >= question_sequence.length
  end

  def finalize!
    return false unless complete?
    
    # Validate all required parameters are collected
    required_params = element.nrm_item&.required_parameters || []
    missing_params = required_params - collected_parameters.keys
    
    if missing_params.any?
      errors.add(:base, "Missing required parameters: #{missing_params.join(', ')}")
      return false
    end

    update!(
      status: "completed",
      completed_at: Time.current,
      final_parameters: collected_parameters
    )
  end

  def mark_as_completed!
    update!(status: "completed", completed_at: Time.current)
  end

  def mark_as_paused!
    update!(status: "paused", paused_at: Time.current)
  end

  private

  def update_question_sequence_based_on_answer(question, answer_data)
    # Implement skip logic based on conditional questions
    if question.has_conditional_logic?
      skip_logic = question.skip_logic
      
      skip_logic.each do |condition|
        if condition["if"] == answer_data["value"]
          # Remove questions that should be skipped
          questions_to_skip = condition["skip_questions"]
          questions_to_skip.each do |skip_id|
            question_sequence.reject! { |q| q["id"] == skip_id }
          end
        end
      end
      
      save!
    end
  end
end
```

### 3. Question Model
```ruby
# app/models/question.rb
class Question
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :id, :string
  attribute :text, :string
  attribute :type, :string
  attribute :required, :boolean, default: true
  attribute :options, :string
  attribute :validation_rules, :string
  attribute :help_text, :string
  attribute :parameter_key, :string
  attribute :conditional_logic, :string
  attribute :context, :string

  def initialize(question_data)
    super(question_data)
  end

  def to_hash
    {
      "id" => id,
      "text" => text,
      "type" => type,
      "required" => required,
      "options" => parsed_options,
      "validation_rules" => parsed_validation_rules,
      "help_text" => help_text,
      "parameter_key" => parameter_key,
      "conditional_logic" => parsed_conditional_logic,
      "context" => context
    }
  end

  def validate_answer(answer_data)
    errors = []
    value = answer_data["value"]

    # Check required
    if required && (value.nil? || value.to_s.strip.empty?)
      errors << "This field is required"
      return { valid: false, errors: errors }
    end

    # Type-specific validation
    case type
    when "number"
      validate_number(value, errors)
    when "email"
      validate_email(value, errors)
    when "select"
      validate_select(value, errors)
    when "multi_select"
      validate_multi_select(value, errors)
    when "date"
      validate_date(value, errors)
    end

    # Custom validation rules
    apply_custom_validations(value, errors)

    { valid: errors.empty?, errors: errors }
  end

  def has_conditional_logic?
    conditional_logic.present?
  end

  def skip_logic
    parsed_conditional_logic["skip_logic"] || []
  end

  private

  def parsed_options
    return [] unless options.present?
    JSON.parse(options) rescue []
  end

  def parsed_validation_rules
    return {} unless validation_rules.present?
    JSON.parse(validation_rules) rescue {}
  end

  def parsed_conditional_logic
    return {} unless conditional_logic.present?
    JSON.parse(conditional_logic) rescue {}
  end

  def validate_number(value, errors)
    return if value.blank?
    
    begin
      num_value = Float(value)
      rules = parsed_validation_rules
      
      if rules["min"] && num_value < rules["min"]
        errors << "Must be at least #{rules['min']}"
      end
      
      if rules["max"] && num_value > rules["max"]
        errors << "Must be no more than #{rules['max']}"
      end
    rescue ArgumentError
      errors << "Must be a valid number"
    end
  end

  def validate_email(value, errors)
    return if value.blank?
    
    unless value.match?(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)
      errors << "Must be a valid email address"
    end
  end

  def validate_select(value, errors)
    return if value.blank?
    
    valid_options = parsed_options.map { |opt| opt["value"] }
    unless valid_options.include?(value)
      errors << "Must select a valid option"
    end
  end

  def validate_multi_select(value, errors)
    return if value.blank?
    
    selected_values = value.is_a?(Array) ? value : [value]
    valid_options = parsed_options.map { |opt| opt["value"] }
    
    invalid_selections = selected_values - valid_options
    if invalid_selections.any?
      errors << "Invalid selections: #{invalid_selections.join(', ')}"
    end
  end

  def validate_date(value, errors)
    return if value.blank?
    
    begin
      Date.parse(value)
    rescue ArgumentError
      errors << "Must be a valid date"
    end
  end

  def apply_custom_validations(value, errors)
    rules = parsed_validation_rules
    
    if rules["pattern"] && value.present?
      pattern = Regexp.new(rules["pattern"])
      unless value.match?(pattern)
        errors << (rules["pattern_message"] || "Invalid format")
      end
    end
    
    if rules["custom_validation"]
      # Apply custom validation logic
      case rules["custom_validation"]
      when "positive_number"
        if value.present? && value.to_f <= 0
          errors << "Must be a positive number"
        end
      when "dimension_format"
        unless value.blank? || value.match?(/^\d+(\.\d+)?\s*(mm|cm|m|ft|in)$/)
          errors << "Must be in format like '2.5m' or '1500mm'"
        end
      end
    end
  end
end
```

### 4. Q&A Interface View
```erb
<!-- app/views/qa_sessions/show.html.erb -->
<% content_for :title, "Parameter Collection - #{@element.name}" %>

<div class="max-w-3xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
  <!-- Header -->
  <div class="mb-8">
    <div class="flex items-center justify-between">
      <div>
        <h1 class="text-2xl font-bold text-gray-900">Parameter Collection</h1>
        <p class="mt-1 text-sm text-gray-500">
          Collecting parameters for: <strong><%= @element.name %></strong>
        </p>
      </div>
      
      <div class="flex space-x-3">
        <button type="button" 
                class="btn btn-secondary"
                data-controller="qa-session"
                data-action="click->qa-session#saveAndExit">
          Save & Resume Later
        </button>
      </div>
    </div>

    <!-- Progress Bar -->
    <div class="mt-6">
      <div class="flex items-center justify-between text-sm text-gray-600 mb-2">
        <span>Progress</span>
        <span><%= @progress.round(1) %>% complete</span>
      </div>
      <div class="bg-gray-200 rounded-full h-2">
        <div class="bg-blue-600 h-2 rounded-full transition-all duration-300" 
             style="width: <%= @progress %>%"></div>
      </div>
    </div>
  </div>

  <!-- Q&A Container -->
  <div id="qa-container" 
       data-controller="qa-session"
       data-qa-session-element-id-value="<%= @element.id %>"
       data-qa-session-session-id-value="<%= @qa_session.id %>">
    
    <% if @qa_session.complete? %>
      <%= render "completion_summary", qa_session: @qa_session %>
    <% else %>
      <%= render "question_form", question: @current_question %>
    <% end %>
  </div>

  <!-- Question History Sidebar -->
  <div class="mt-8 lg:mt-0 lg:absolute lg:right-8 lg:top-24 lg:w-80">
    <div class="bg-gray-50 rounded-lg p-4">
      <h3 class="text-sm font-medium text-gray-900 mb-3">Answered Questions</h3>
      
      <% if @answered_questions.any? %>
        <div class="space-y-2">
          <% @answered_questions.each do |answer| %>
            <div class="text-xs bg-white rounded p-2">
              <p class="font-medium text-gray-700">
                <%= truncate(answer.question_data["text"], length: 50) %>
              </p>
              <p class="text-gray-500 mt-1">
                <% if answer.answer_data["skipped"] %>
                  <em>Skipped: <%= answer.answer_data["skip_reason"] %></em>
                <% else %>
                  <%= truncate(answer.answer_data["value"].to_s, length: 30) %>
                <% end %>
              </p>
            </div>
          <% end %>
        </div>
      <% else %>
        <p class="text-xs text-gray-500">No questions answered yet</p>
      <% end %>
    </div>
  </div>
</div>
```

### 5. Question Form Component
```erb
<!-- app/views/qa_sessions/_question_form.html.erb -->
<div class="bg-white rounded-lg border border-gray-200 shadow-sm p-6"
     id="current-question"
     data-qa-session-target="questionForm">
  
  <div class="mb-6">
    <h2 class="text-lg font-medium text-gray-900 mb-2">
      <%= question.text %>
    </h2>
    
    <% if question.help_text.present? %>
      <p class="text-sm text-gray-600 mb-4">
        <%= question.help_text %>
      </p>
    <% end %>

    <% if question.context.present? %>
      <div class="bg-blue-50 border border-blue-200 rounded-md p-3 mb-4">
        <p class="text-xs text-blue-800">
          <strong>Context:</strong> <%= question.context %>
        </p>
      </div>
    <% end %>
  </div>

  <%= form_with url: "#", 
                local: false, 
                id: "question-form",
                data: { 
                  qa_session_target: "form",
                  action: "submit->qa-session#submitAnswer"
                } do |form| %>
    
    <%= hidden_field_tag :question_id, question.id %>
    
    <!-- Error Container -->
    <div id="question-errors" class="hidden mb-4">
      <!-- Errors will be inserted here -->
    </div>

    <!-- Answer Input -->
    <div class="mb-6">
      <%= render "question_input", question: question, form: form %>
    </div>

    <!-- Action Buttons -->
    <div class="flex items-center justify-between">
      <div class="flex space-x-3">
        <% if @qa_session.current_question_index > 0 %>
          <button type="button" 
                  class="btn btn-secondary"
                  data-action="click->qa-session#goBack">
            <svg class="w-4 h-4 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
            </svg>
            Back
          </button>
        <% end %>
        
        <% unless question.required %>
          <button type="button" 
                  class="btn btn-outline"
                  data-action="click->qa-session#skipQuestion"
                  data-question-id="<%= question.id %>">
            Skip This Question
          </button>
        <% end %>
      </div>

      <button type="submit" 
              class="btn btn-primary"
              data-qa-session-target="submitButton">
        <span data-qa-session-target="submitText">Continue</span>
        <svg class="w-4 h-4 ml-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
        </svg>
      </button>
    </div>
  <% end %>
</div>
```

## Technical Notes
- Progressive disclosure reduces cognitive load by showing only relevant questions
- Skip logic dynamically adapts question flow based on previous answers
- Real-time validation provides immediate feedback to users
- Save and resume functionality prevents data loss during long sessions
- Mobile-optimized interface works well on smartphones and tablets

## Definition of Done
- [ ] Q&A workflow guides users through parameter collection
- [ ] Progressive disclosure shows only relevant questions
- [ ] Skip logic adapts based on previous answers
- [ ] Real-time validation works for all question types
- [ ] Save and resume functionality preserves progress
- [ ] Mobile interface provides good user experience
- [ ] Code review completed