# Ticket 1: Quantity Calculation Engine

**Epic**: M7 Quantity Calculation  
**Story Points**: 5  
**Dependencies**: M-06 (Parameter collection)

## Description
Develop robust quantity calculation engine that processes assembly formulas, validates inputs, performs calculations with error handling, and maintains audit trails for all quantity determinations.

## Acceptance Criteria
- [ ] Formula evaluation engine with safety constraints
- [ ] Input validation and unit conversion
- [ ] Calculation audit trails and version control
- [ ] Error handling for invalid formulas/inputs
- [ ] Background job processing for complex calculations
- [ ] Real-time calculation updates via Turbo Streams

## Code to be Written

### 1. Quantity Model
```ruby
# app/models/quantity.rb
class Quantity < ApplicationRecord
  belongs_to :element
  belongs_to :assembly
  has_many :boq_lines, dependent: :destroy

  validates :calculated_amount, presence: true, numericality: { greater_than: 0 }
  validates :unit, presence: true
  validates :calculation_data, presence: true

  scope :for_element, ->(element) { where(element: element) }
  scope :calculated, -> { where.not(calculated_amount: nil) }

  def recalculate!
    result = AssemblyCalculator.new(assembly, element.combined_params).calculate
    update!(
      calculated_amount: result[:amount],
      unit: result[:unit],
      calculation_data: result[:breakdown],
      calculated_at: Time.current
    )
  end

  def calculation_breakdown
    calculation_data['steps'] || []
  end

  def inputs_used
    calculation_data['inputs'] || {}
  end
end
```

### 2. Assembly Calculator Service
```ruby
# app/services/assembly_calculator.rb
class AssemblyCalculator
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :assembly
  attribute :parameters, :hash, default: {}

  def calculate
    validate_inputs!
    
    {
      amount: evaluate_formula,
      unit: assembly.unit,
      breakdown: calculation_breakdown,
      inputs: normalized_parameters,
      formula_used: assembly.formula,
      calculated_at: Time.current
    }
  end

  private

  def evaluate_formula
    safe_eval = SafeEval.new(
      formula: assembly.formula,
      variables: normalized_parameters,
      allowed_functions: %w[sqrt pow abs min max round]
    )
    
    result = safe_eval.evaluate
    raise CalculationError, "Formula returned invalid result" unless result.is_a?(Numeric) && result > 0
    
    result.round(4)
  end

  def validate_inputs!
    required_params = assembly.required_parameters
    missing_params = required_params - parameters.keys.map(&:to_s)
    
    if missing_params.any?
      raise ValidationError, "Missing required parameters: #{missing_params.join(', ')}"
    end
    
    validate_parameter_types!
    validate_parameter_ranges!
  end

  def normalized_parameters
    @normalized_parameters ||= parameters.transform_values do |value|
      case value
      when String
        value.to_f
      when Numeric
        value.to_f
      else
        raise ValidationError, "Invalid parameter type: #{value.class}"
      end
    end
  end

  def calculation_breakdown
    steps = []
    
    # Record input values
    normalized_parameters.each do |key, value|
      steps << {
        step: "Input: #{key}",
        value: value,
        unit: parameter_unit(key)
      }
    end
    
    # Record formula evaluation
    steps << {
      step: "Formula: #{assembly.formula}",
      value: evaluate_formula,
      unit: assembly.unit
    }
    
    steps
  end

  def parameter_unit(parameter_name)
    assembly.inputs_schema.dig('properties', parameter_name.to_s, 'unit') || 'unknown'
  end
end
```

### 3. Safe Formula Evaluator
```ruby
# app/services/safe_eval.rb
class SafeEval
  ALLOWED_OPERATORS = %w[+ - * / ( ) ** %].freeze
  ALLOWED_FUNCTIONS = %w[sqrt pow abs min max round sin cos tan].freeze
  MATH_CONSTANTS = { 'PI' => Math::PI, 'E' => Math::E }.freeze

  attr_reader :formula, :variables, :allowed_functions

  def initialize(formula:, variables: {}, allowed_functions: [])
    @formula = formula.to_s.strip
    @variables = variables.stringify_keys
    @allowed_functions = allowed_functions.map(&:to_s)
  end

  def evaluate
    validate_formula_safety!
    
    # Replace variables in formula
    processed_formula = substitute_variables
    
    # Use Ruby's eval in restricted context
    binding = create_safe_binding
    result = binding.eval(processed_formula)
    
    validate_result!(result)
    result
  end

  private

  def validate_formula_safety!
    # Check for dangerous patterns
    dangerous_patterns = [
      /system|exec|eval|send|const_get|class_eval|instance_eval/i,
      /File|Dir|IO|Process|Kernel/i,
      /\$|`|require|load|open/i
    ]
    
    dangerous_patterns.each do |pattern|
      if formula.match?(pattern)
        raise SecurityError, "Formula contains potentially dangerous operations"
      end
    end
    
    # Validate only allowed characters
    allowed_chars = /\A[a-zA-Z0-9_+\-*\/().\s#{Regexp.escape('**')}]+\z/
    unless formula.match?(allowed_chars)
      raise SecurityError, "Formula contains disallowed characters"
    end
  end

  def substitute_variables
    result = formula.dup
    
    # Replace variables
    variables.each do |var_name, value|
      # Use word boundaries to avoid partial replacements
      result.gsub!(/\b#{Regexp.escape(var_name)}\b/, value.to_s)
    end
    
    # Replace constants
    MATH_CONSTANTS.each do |constant, value|
      result.gsub!(/\b#{Regexp.escape(constant)}\b/, value.to_s)
    end
    
    # Replace allowed functions
    allowed_functions.each do |func|
      next unless ALLOWED_FUNCTIONS.include?(func)
      result.gsub!(/\b#{Regexp.escape(func)}\(/i, "Math.#{func}(")
    end
    
    result
  end

  def create_safe_binding
    # Create minimal binding with only Math module
    Object.new.instance_eval do
      def Math.method_missing(name, *args)
        if %w[sqrt pow abs min max round sin cos tan].include?(name.to_s)
          super
        else
          raise NoMethodError, "undefined method `#{name}' for Math"
        end
      end
      
      binding
    end
  end

  def validate_result!(result)
    unless result.is_a?(Numeric)
      raise CalculationError, "Formula must return a numeric value, got #{result.class}"
    end
    
    if result.infinite? || result.nan?
      raise CalculationError, "Formula returned invalid numeric value"
    end
    
    if result < 0
      raise CalculationError, "Quantities cannot be negative"
    end
  end
end
```

### 4. Quantity Calculation Job
```ruby
# app/jobs/quantity_calculation_job.rb
class QuantityCalculationJob < ApplicationJob
  include JobErrorHandling
  
  queue_as :calculations
  
  retry_on CalculationError, wait: 30.seconds, attempts: 3
  discard_on ValidationError, SecurityError

  def perform(element)
    @element = element
    
    Rails.logger.info("Starting quantity calculation", {
      element_id: element.id,
      project_id: element.project.id
    })
    
    # Find applicable assemblies
    assemblies = find_applicable_assemblies
    
    if assemblies.empty?
      Rails.logger.warn("No applicable assemblies found", { element_id: element.id })
      return
    end
    
    # Calculate quantities for each assembly
    results = calculate_quantities_for_assemblies(assemblies)
    
    broadcast_completion(results)
    
    Rails.logger.info("Quantity calculation completed", {
      element_id: element.id,
      quantities_calculated: results.count
    })
  end

  private

  def find_applicable_assemblies
    # Find assemblies based on element type and NRM suggestions
    Assembly.joins(:nrm_item)
            .where(nrm_items: { tags: [@element.element_type] })
            .where('assemblies.region IS NULL OR assemblies.region = ?', @element.project.region)
  end

  def calculate_quantities_for_assemblies(assemblies)
    results = []
    
    assemblies.each do |assembly|
      begin
        calculation_result = AssemblyCalculator.new(assembly, @element.combined_params).calculate
        
        quantity = @element.quantities.find_or_initialize_by(assembly: assembly)
        quantity.update!(
          calculated_amount: calculation_result[:amount],
          unit: calculation_result[:unit],
          calculation_data: calculation_result,
          calculated_at: Time.current
        )
        
        results << quantity
        
      rescue ValidationError => e
        Rails.logger.warn("Validation error for assembly #{assembly.id}", {
          element_id: @element.id,
          assembly_id: assembly.id,
          error: e.message
        })
        # Continue with other assemblies
      end
    end
    
    results
  end

  def broadcast_completion(quantities)
    Turbo::StreamsChannel.broadcast_action_to(
      "project_#{@element.project.id}",
      action: :replace,
      target: "element_#{@element.id}_quantities",
      partial: "shared/element_quantities",
      locals: { element: @element, quantities: quantities }
    )
  end
end
```

### 5. Custom Error Classes
```ruby
# app/services/calculation_errors.rb
class CalculationError < StandardError; end
class ValidationError < StandardError; end
class FormulaError < StandardError; end
```

## Technical Notes
- Safe formula evaluation prevents code injection
- Detailed audit trails support debugging and compliance
- Background processing handles complex calculations
- Real-time updates keep UI synchronized
- Comprehensive error handling covers edge cases

## Definition of Done
- [ ] Formula evaluation is secure and accurate
- [ ] Input validation prevents invalid calculations
- [ ] Audit trails capture all calculation steps
- [ ] Background jobs process calculations efficiently
- [ ] Error handling covers all scenarios
- [ ] Real-time updates work via Turbo Streams
- [ ] Test coverage exceeds 95%
- [ ] Code review completed