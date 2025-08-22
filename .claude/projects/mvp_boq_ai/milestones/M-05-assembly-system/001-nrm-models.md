# Ticket 1: NRM Database Models

**Epic**: M5 NRM Database Integration  
**Story Points**: 3  
**Dependencies**: M-04 (Element verification)

## Description
Create models for NRM (New Rules of Measurement) database integration that supports AI-driven NRM code suggestions, standardized measurement rules, and regional rate mappings.

## Acceptance Criteria
- [ ] NRM items model with hierarchical structure
- [ ] Assembly definitions with measurement rules
- [ ] AI service integration for NRM suggestions
- [ ] Regional compliance validation
- [ ] Search and filtering capabilities

## Code to be Written

### 1. NRM Item Model
```ruby
# app/models/nrm_item.rb
class NrmItem < ApplicationRecord
  has_many :assemblies, dependent: :destroy
  has_many :elements, through: :assemblies
  belongs_to :parent, class_name: 'NrmItem', optional: true
  has_many :children, class_name: 'NrmItem', foreign_key: 'parent_id'

  validates :code, presence: true, uniqueness: true
  validates :title, presence: true
  validates :unit, presence: true
  validates :level, inclusion: { in: 1..4 }

  scope :top_level, -> { where(level: 1) }
  scope :for_element_type, ->(type) { where('tags @> ?', [type].to_json) }
  scope :search, ->(term) { where('title ILIKE ? OR description ILIKE ?', "%#{term}%", "%#{term}%") }

  def hierarchy_path
    path = []
    current = self
    while current
      path.unshift(current)
      current = current.parent
    end
    path
  end

  def full_code_path
    hierarchy_path.map(&:code).join('.')
  end
end
```

### 2. Assembly Model
```ruby
# app/models/assembly.rb
class Assembly < ApplicationRecord
  belongs_to :nrm_item
  has_many :quantities, dependent: :destroy
  has_many :elements, through: :quantities

  validates :name, presence: true
  validates :formula, presence: true
  validates :unit, presence: true
  validates :inputs_schema, presence: true

  def calculate_quantity(params)
    AssemblyCalculator.new(self, params).calculate
  end

  def required_parameters
    inputs_schema['required'] || []
  end
end
```

### 3. AI NRM Suggestion Service
```ruby
# app/services/ai/nrm_suggestion_service.rb
module Ai
  class NrmSuggestionService < BaseService
    def initialize(element)
      super()
      @element = element
    end

    def call
      suggestions = generate_suggestions
      rank_and_filter_suggestions(suggestions)
    end

    private

    def generate_suggestions
      # AI-powered NRM code suggestions based on element data
      prompt = build_nrm_prompt
      response = client.chat(parameters: {
        model: model,
        messages: [{ role: "user", content: prompt }],
        max_tokens: 1000,
        temperature: 0.1
      })
      
      parse_nrm_response(response)
    end
  end
end
```

## Technical Notes
- Hierarchical NRM structure supports nested classification
- AI service provides intelligent code suggestions
- Flexible schema validation for different measurement types

## Definition of Done
- [ ] Models pass all tests
- [ ] AI integration working
- [ ] Search functionality operational
- [ ] Performance optimized with indexes
- [ ] Code review completed