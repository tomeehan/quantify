# Ticket 1: Dynamic Question Forms

**Epic**: M6 Question Resolution  
**Story Points**: 4  
**Dependencies**: M-05 (NRM integration)

## Description
Create dynamic form system that generates context-specific questions to collect missing parameters for quantity calculations, using JSON schema-driven forms with conditional logic.

## Acceptance Criteria
- [ ] JSON schema-based form generation
- [ ] Progressive disclosure of questions
- [ ] Context-aware parameter collection
- [ ] Real-time validation and suggestions
- [ ] Mobile-optimized question flow

## Code to be Written

### 1. Question Generator Service
```ruby
# app/services/question_generator.rb
class QuestionGenerator
  attr_reader :element, :assembly

  def initialize(element, assembly)
    @element = element
    @assembly = assembly
  end

  def generate_questions
    missing_params = find_missing_parameters
    build_question_forms(missing_params)
  end

  private

  def find_missing_parameters
    required = assembly.required_parameters
    provided = element.combined_params.keys
    required - provided
  end

  def build_question_forms(params)
    params.map do |param|
      QuestionBuilder.new(param, element, assembly).build
    end
  end
end
```

### 2. Dynamic Form Builder
```ruby
# app/components/dynamic_form_component.rb
class DynamicFormComponent < ViewComponent::Base
  attr_reader :element, :questions, :form_id

  def initialize(element:, questions:, form_id: nil)
    @element = element
    @questions = questions
    @form_id = form_id || "dynamic_form_#{element.id}"
  end

  private

  def form_fields_for_question(question)
    case question[:type]
    when 'dimension'
      dimension_field(question)
    when 'material_choice'
      select_field(question)
    when 'boolean'
      checkbox_field(question)
    else
      text_field(question)
    end
  end
end
```

### 3. Question Controller
```ruby
# app/controllers/projects/questions_controller.rb
class Projects::QuestionsController < ApplicationController
  def show
    @element = current_account.projects.find(params[:project_id])
                            .elements.find(params[:element_id])
    @questions = QuestionGenerator.new(@element, @assembly).generate_questions
  end

  def update
    @element = find_element
    if @element.update(user_params: updated_params)
      redirect_to next_question_or_summary
    else
      render :show, status: :unprocessable_entity
    end
  end
end
```

## Technical Notes
- Schema-driven approach allows flexible question types
- Progressive disclosure improves user experience
- Context awareness reduces irrelevant questions
- Real-time validation prevents invalid inputs

## Definition of Done
- [ ] Form generation works for all parameter types
- [ ] Progressive disclosure functions correctly
- [ ] Validation provides helpful feedback
- [ ] Mobile interface is intuitive
- [ ] Test coverage exceeds 90%
- [ ] Code review completed