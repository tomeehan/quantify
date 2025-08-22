# Ticket 2: Quantity Calculation Engine

**Epic**: M7 Quantity Calculation  
**Story Points**: 8  
**Dependencies**: 001-quantity-calculation-engine.md

## Description
Implement a robust calculation engine that safely evaluates assembly formulas, applies element parameters, and generates accurate quantity calculations with comprehensive audit trails and error handling.

## Acceptance Criteria
- [ ] Safe formula evaluation engine with sandboxed execution
- [ ] Support for complex mathematical formulas and functions
- [ ] Real-time calculation updates when parameters change
- [ ] Comprehensive error handling and validation
- [ ] Calculation audit trail with step-by-step breakdown
- [ ] Background processing for complex calculations
- [ ] Unit conversion and standardization

## Code to be Written

### 1. Calculation Engine Service
```ruby
# app/services/quantity_calculation_engine.rb
class QuantityCalculationEngine
  include ActiveModel::Model
  
  class CalculationError < StandardError; end
  class FormulaError < CalculationError; end
  class ParameterError < CalculationError; end
  class UnitError < CalculationError; end

  attr_reader :element, :assembly, :parameters, :calculation_context

  def initialize(element, assembly = nil)
    @element = element
    @assembly = assembly || element.nrm_item&.primary_assembly
    @parameters = element.clarification_parameters || {}
    @calculation_context = build_calculation_context
  end

  def calculate_quantity
    validate_inputs!
    
    calculation_result = perform_calculation
    
    # Create quantity record with audit trail
    quantity = create_quantity_record(calculation_result)
    
    # Log calculation details for audit
    log_calculation(quantity, calculation_result)
    
    quantity
  rescue => error
    handle_calculation_error(error)
  end

  def self.recalculate_all_for_element(element)
    element.quantities.destroy_all
    
    element.nrm_item&.assemblies&.each do |assembly|
      engine = new(element, assembly)
      engine.calculate_quantity
    end
  end

  private

  def validate_inputs!
    raise ParameterError, "Element is required" unless element
    raise ParameterError, "Assembly is required" unless assembly
    raise ParameterError, "Assembly formula is missing" unless assembly.formula.present?
    
    # Validate required parameters are present
    required_params = assembly.inputs_schema["required"] || []
    missing_params = required_params - parameters.keys.map(&:to_s)
    
    if missing_params.any?
      raise ParameterError, "Missing required parameters: #{missing_params.join(', ')}"
    end
    
    # Validate parameter types and values
    validate_parameter_types!
  end

  def validate_parameter_types!
    schema_properties = assembly.inputs_schema["properties"] || {}
    
    schema_properties.each do |param_name, param_schema|
      next unless parameters.key?(param_name.to_s)
      
      value = parameters[param_name.to_s]
      param_type = param_schema["type"]
      
      case param_type
      when "number"
        begin
          Float(value)
        rescue ArgumentError
          raise ParameterError, "Parameter '#{param_name}' must be a number, got: #{value}"
        end
      when "integer"
        begin
          Integer(value)
        rescue ArgumentError
          raise ParameterError, "Parameter '#{param_name}' must be an integer, got: #{value}"
        end
      when "string"
        unless value.is_a?(String) || value.respond_to?(:to_s)
          raise ParameterError, "Parameter '#{param_name}' must be a string, got: #{value.class}"
        end
      end
    end
  end

  def perform_calculation
    # Prepare the calculation environment
    calculator = FormulaCalculator.new(assembly.formula, calculation_context)
    
    # Execute the formula
    result = calculator.evaluate
    
    # Validate result
    validate_calculation_result(result)
    
    # Convert to standard units if needed
    standardized_result = convert_to_standard_units(result)
    
    {
      raw_result: result,
      standardized_result: standardized_result,
      unit: assembly.unit,
      calculation_steps: calculator.calculation_steps,
      formula_used: assembly.formula,
      parameters_used: parameters.dup,
      calculation_metadata: {
        calculated_at: Time.current,
        assembly_id: assembly.id,
        element_id: element.id
      }
    }
  end

  def build_calculation_context
    context = parameters.dup.with_indifferent_access
    
    # Add standard mathematical functions
    context.merge!({
      'PI' => Math::PI,
      'E' => Math::E,
      'sqrt' => ->(x) { Math.sqrt(x) },
      'pow' => ->(x, y) { x ** y },
      'abs' => ->(x) { x.abs },
      'round' => ->(x, precision = 2) { x.round(precision) },
      'ceil' => ->(x) { x.ceil },
      'floor' => ->(x) { x.floor },
      'max' => ->(x, y) { [x, y].max },
      'min' => ->(x, y) { [x, y].min }
    })
    
    # Add unit conversion functions
    context.merge!(unit_conversion_functions)
    
    # Add element-specific context
    context['element_type'] = element.extracted_data&.dig('type')
    context['material'] = element.extracted_data&.dig('material')
    
    context
  end

  def unit_conversion_functions
    {
      'to_mm' => ->(value, from_unit) { UnitConverter.convert(value, from_unit, 'mm') },
      'to_m' => ->(value, from_unit) { UnitConverter.convert(value, from_unit, 'm') },
      'to_m2' => ->(value, from_unit) { UnitConverter.convert(value, from_unit, 'm2') },
      'to_m3' => ->(value, from_unit) { UnitConverter.convert(value, from_unit, 'm3') }
    }
  end

  def validate_calculation_result(result)
    unless result.is_a?(Numeric)
      raise CalculationError, "Formula must return a numeric value, got: #{result.class}"
    end
    
    if result.nan? || result.infinite?
      raise CalculationError, "Formula produced invalid result: #{result}"
    end
    
    if result < 0
      Rails.logger.warn "Negative quantity calculated for element #{element.id}: #{result}"
    end
  end

  def convert_to_standard_units(result)
    # Convert result to standard unit for the assembly
    target_unit = assembly.unit
    
    # For now, assume result is already in correct unit
    # In a real implementation, you'd detect the unit and convert
    result
  end

  def create_quantity_record(calculation_result)
    Quantity.create!(
      element: element,
      assembly: assembly,
      quantity: calculation_result[:standardized_result],
      unit: calculation_result[:unit],
      calculation_metadata: calculation_result[:calculation_metadata],
      formula_used: calculation_result[:formula_used],
      parameters_used: calculation_result[:parameters_used],
      calculation_steps: calculation_result[:calculation_steps]
    )
  end

  def log_calculation(quantity, calculation_result)
    QuantityCalculationAudit.create!(
      quantity: quantity,
      element: element,
      assembly: assembly,
      calculated_by: :system,
      calculation_method: :formula_evaluation,
      input_parameters: calculation_result[:parameters_used],
      formula_used: calculation_result[:formula_used],
      calculation_steps: calculation_result[:calculation_steps],
      result_value: calculation_result[:standardized_result],
      result_unit: calculation_result[:unit],
      calculation_timestamp: Time.current,
      calculation_duration_ms: 0, # Would be measured in real implementation
      metadata: {
        assembly_version: assembly.version,
        engine_version: "1.0.0"
      }
    )
  end

  def handle_calculation_error(error)
    Rails.logger.error "Calculation failed for element #{element.id}: #{error.message}"
    Rails.logger.error error.backtrace.join("\n")
    
    # Create error record for troubleshooting
    QuantityCalculationError.create!(
      element: element,
      assembly: assembly,
      error_type: error.class.name,
      error_message: error.message,
      parameters_attempted: parameters,
      formula_attempted: assembly&.formula,
      occurred_at: Time.current
    )
    
    raise error
  end
end
```

### 2. Formula Calculator
```ruby
# app/services/formula_calculator.rb
class FormulaCalculator
  attr_reader :formula, :context, :calculation_steps

  def initialize(formula, context = {})
    @formula = formula
    @context = context.with_indifferent_access
    @calculation_steps = []
  end

  def evaluate
    # Parse and validate the formula
    parsed_formula = parse_formula(formula)
    
    # Evaluate in a safe environment
    result = safe_evaluate(parsed_formula)
    
    record_final_step(result)
    
    result
  end

  private

  def parse_formula(formula_string)
    # Simple formula parser - in production, use a proper parser like Parslet
    # For now, handle basic mathematical expressions with variables
    
    # Replace variables with their values
    processed_formula = formula_string.dup
    
    context.each do |key, value|
      # Only replace if value is numeric or it's a known function
      if value.is_a?(Numeric) || value.respond_to?(:call)
        # Use word boundaries to avoid partial replacements
        processed_formula.gsub!(/\b#{Regexp.escape(key.to_s)}\b/, value.to_s)
      end
    end
    
    record_step("Formula after variable substitution", processed_formula)
    
    processed_formula
  end

  def safe_evaluate(formula_expression)
    # Create a safe evaluation environment
    # In production, use a proper sandboxed evaluator
    
    # For this example, we'll use a simple but limited approach
    # Replace with a proper math expression evaluator in production
    
    begin
      # Remove any dangerous operations
      sanitized_formula = sanitize_formula(formula_expression)
      
      # Evaluate using Ruby's eval in a controlled manner
      # Note: In production, use a proper math expression library
      result = evaluate_math_expression(sanitized_formula)
      
      record_step("Final calculation", "#{sanitized_formula} = #{result}")
      
      result
    rescue => error
      record_step("Calculation error", error.message)
      raise QuantityCalculationEngine::FormulaError, "Formula evaluation failed: #{error.message}"
    end
  end

  def sanitize_formula(formula)
    # Remove any potentially dangerous operations
    dangerous_patterns = [
      /system/i, /exec/i, /eval/i, /load/i, /require/i,
      /class/i, /module/i, /def/i, /proc/i, /lambda/i
    ]
    
    dangerous_patterns.each do |pattern|
      if formula.match?(pattern)
        raise QuantityCalculationEngine::FormulaError, "Formula contains dangerous operations"
      end
    end
    
    # Only allow mathematical operations and known functions
    allowed_chars = /\A[0-9\+\-\*\/\(\)\.\s\w]+\z/
    unless formula.match?(allowed_chars)
      raise QuantityCalculationEngine::FormulaError, "Formula contains invalid characters"
    end
    
    formula
  end

  def evaluate_math_expression(expression)
    # Simple math expression evaluator
    # In production, use a library like Dentaku or similar
    
    # Handle basic mathematical operations
    # This is a simplified implementation
    
    # Replace function calls with actual calculations
    expression = process_function_calls(expression)
    
    # Evaluate the final mathematical expression
    # Note: Using eval here is for demonstration - use a proper math library in production
    eval(expression)
  end

  def process_function_calls(expression)
    # Process mathematical functions
    processed = expression.dup
    
    # Handle sqrt function
    processed.gsub!(/sqrt\(([^)]+)\)/) do
      arg = $1.to_f
      result = Math.sqrt(arg)
      record_step("Function call", "sqrt(#{arg}) = #{result}")
      result.to_s
    end
    
    # Handle pow function  
    processed.gsub!(/pow\(([^,]+),([^)]+)\)/) do
      base = $1.to_f
      exponent = $2.to_f
      result = base ** exponent
      record_step("Function call", "pow(#{base}, #{exponent}) = #{result}")
      result.to_s
    end
    
    # Handle other mathematical functions similarly
    
    processed
  end

  def record_step(description, details)
    @calculation_steps << {
      step: @calculation_steps.length + 1,
      description: description,
      details: details,
      timestamp: Time.current.iso8601
    }
  end

  def record_final_step(result)
    record_step("Final result", result.to_s)
  end
end
```

### 3. Quantity Calculation Audit Model
```ruby
# app/models/quantity_calculation_audit.rb
class QuantityCalculationAudit < ApplicationRecord
  belongs_to :quantity
  belongs_to :element
  belongs_to :assembly

  validates :calculation_method, presence: true
  validates :input_parameters, presence: true
  validates :result_value, presence: true
  validates :result_unit, presence: true

  serialize :input_parameters, JSON
  serialize :calculation_steps, JSON
  serialize :metadata, JSON

  enum calculated_by: { system: 0, user: 1, ai: 2 }
  enum calculation_method: { 
    formula_evaluation: 0, 
    manual_entry: 1, 
    ai_estimation: 2,
    external_calculation: 3 
  }

  scope :recent, -> { order(created_at: :desc) }
  scope :for_element, ->(element) { where(element: element) }

  def calculation_summary
    "#{calculation_method.humanize} calculation of #{result_value} #{result_unit} " \
    "for #{assembly.title} using formula: #{formula_used}"
  end

  def parameters_summary
    input_parameters.map { |k, v| "#{k}: #{v}" }.join(", ")
  end

  def execution_time
    return "N/A" unless calculation_duration_ms
    
    if calculation_duration_ms < 1000
      "#{calculation_duration_ms}ms"
    else
      "#{(calculation_duration_ms / 1000.0).round(2)}s"
    end
  end
end
```

### 4. Migration for Calculation Audits
```ruby
# db/migrate/xxx_create_quantity_calculation_audits.rb
class CreateQuantityCalculationAudits < ActiveRecord::Migration[8.0]
  def change
    create_table :quantity_calculation_audits do |t|
      t.references :quantity, null: false, foreign_key: true
      t.references :element, null: false, foreign_key: true  
      t.references :assembly, null: false, foreign_key: true
      
      t.integer :calculated_by, null: false, default: 0
      t.integer :calculation_method, null: false, default: 0
      
      t.json :input_parameters, null: false
      t.text :formula_used
      t.json :calculation_steps
      
      t.decimal :result_value, precision: 15, scale: 6, null: false
      t.string :result_unit, null: false
      
      t.datetime :calculation_timestamp, null: false
      t.integer :calculation_duration_ms
      
      t.json :metadata

      t.timestamps
    end

    add_index :quantity_calculation_audits, :quantity_id
    add_index :quantity_calculation_audits, :element_id
    add_index :quantity_calculation_audits, :assembly_id
    add_index :quantity_calculation_audits, :calculation_timestamp
    add_index :quantity_calculation_audits, [:element_id, :calculation_timestamp]
  end
end
```

### 5. Calculation Engine Tests
```ruby
# test/services/quantity_calculation_engine_test.rb
require "test_helper"

class QuantityCalculationEngineTest < ActiveSupport::TestCase
  setup do
    @element = elements(:concrete_foundation)
    @assembly = assemblies(:concrete_volume)
    @element.update!(clarification_parameters: {
      "length" => "10.0",
      "width" => "2.0", 
      "height" => "0.3"
    })
  end

  test "calculates quantity successfully" do
    engine = QuantityCalculationEngine.new(@element, @assembly)
    quantity = engine.calculate_quantity
    
    assert quantity.persisted?
    assert_equal 6.0, quantity.quantity # 10 * 2 * 0.3
    assert_equal "m3", quantity.unit
  end

  test "validates required parameters" do
    @element.update!(clarification_parameters: { "length" => "10.0" }) # Missing width, height
    
    engine = QuantityCalculationEngine.new(@element, @assembly)
    
    assert_raises(QuantityCalculationEngine::ParameterError) do
      engine.calculate_quantity
    end
  end

  test "handles formula errors gracefully" do
    @assembly.update!(formula: "invalid_formula")
    
    engine = QuantityCalculationEngine.new(@element, @assembly)
    
    assert_raises(QuantityCalculationEngine::FormulaError) do
      engine.calculate_quantity
    end
    
    # Should create error record
    assert_difference "QuantityCalculationError.count", 1 do
      begin
        engine.calculate_quantity
      rescue QuantityCalculationEngine::FormulaError
        # Expected
      end
    end
  end

  test "creates comprehensive audit trail" do
    engine = QuantityCalculationEngine.new(@element, @assembly)
    
    assert_difference "QuantityCalculationAudit.count", 1 do
      quantity = engine.calculate_quantity
    end
    
    audit = QuantityCalculationAudit.last
    assert_equal @element, audit.element
    assert_equal @assembly, audit.assembly
    assert_equal "formula_evaluation", audit.calculation_method
    assert audit.input_parameters.present?
    assert audit.calculation_steps.present?
  end

  test "recalculates all quantities for element" do
    # Create multiple assemblies for the element
    @element.nrm_item.assemblies.create!(
      title: "Concrete Area",
      formula: "length * width",
      unit: "m2",
      inputs_schema: {
        "required" => ["length", "width"],
        "properties" => {
          "length" => { "type" => "number" },
          "width" => { "type" => "number" }
        }
      }
    )
    
    assert_difference "Quantity.count", 2 do
      QuantityCalculationEngine.recalculate_all_for_element(@element)
    end
  end

  test "handles negative results with warning" do
    @element.update!(clarification_parameters: {
      "length" => "-5.0", # Negative input
      "width" => "2.0",
      "height" => "0.3"
    })
    
    engine = QuantityCalculationEngine.new(@element, @assembly)
    
    # Should still calculate but log warning
    assert_nothing_raised do
      quantity = engine.calculate_quantity
      assert quantity.quantity < 0
    end
  end
end
```

## Technical Notes
- Safe formula evaluation prevents code injection and security issues
- Comprehensive audit trail enables debugging and compliance
- Background processing handles complex calculations without blocking UI
- Unit conversion ensures consistent quantity measurements
- Error handling provides clear feedback for troubleshooting

## Definition of Done
- [ ] Formula evaluation engine works safely and accurately
- [ ] Complex mathematical formulas are supported
- [ ] Calculation audit trail captures all steps
- [ ] Error handling provides clear feedback
- [ ] Background processing works for complex calculations
- [ ] Unit conversion functions correctly
- [ ] All tests pass with >95% coverage
- [ ] Code review completed