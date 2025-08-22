# Ticket 3: Advanced Prompt Engineering

**Epic**: M3 AI Processing & Extraction  
**Story Points**: 4  
**Dependencies**: 001-ai-service-integration.md

## Description
Develop sophisticated prompt engineering capabilities for construction specification analysis. This includes specialized prompts for different element types, context-aware prompting, few-shot learning examples, and dynamic prompt generation based on project context and regional standards.

## Acceptance Criteria
- [ ] Element-type specific prompt templates
- [ ] Context-aware prompting with project and regional information
- [ ] Few-shot learning examples for improved accuracy
- [ ] Dynamic prompt generation based on specification content
- [ ] Regional standards integration (UK NRM, Australian standards, etc.)
- [ ] Prompt versioning and A/B testing capabilities
- [ ] Validation and confidence scoring improvements

## Code to be Written

### 1. Prompt Template Engine
```ruby
# app/services/ai/prompt_engine.rb
module Ai
  class PromptEngine
    include ActionView::Helpers::TextHelper

    attr_reader :element, :project, :options

    def initialize(element, options = {})
      @element = element
      @project = element.project
      @options = options.with_indifferent_access
    end

    def build_system_prompt
      PromptTemplate.new(:system, context).render
    end

    def build_user_prompt
      PromptTemplate.new(:user, context).render
    end

    def build_few_shot_examples
      FewShotExamples.new(element_type: detected_element_type, region: project.region).examples
    end

    private

    def context
      @context ||= {
        element: element,
        project: project,
        detected_element_type: detected_element_type,
        regional_standards: regional_standards,
        specification_complexity: complexity_score,
        few_shot_examples: build_few_shot_examples,
        extraction_focus: extraction_focus_areas,
        validation_rules: validation_rules
      }
    end

    def detected_element_type
      @detected_element_type ||= ElementTypeDetector.new(element).detect
    end

    def regional_standards
      RegionalStandards.for_region(project.region)
    end

    def complexity_score
      SpecificationComplexity.new(element.specification).score
    end

    def extraction_focus_areas
      ElementExtractionRules.for_type(detected_element_type)
    end

    def validation_rules
      ValidationRules.for_type_and_region(detected_element_type, project.region)
    end
  end
end
```

### 2. Prompt Template System
```ruby
# app/services/ai/prompt_template.rb
module Ai
  class PromptTemplate
    TEMPLATE_PATH = Rails.root.join("config", "ai_prompts")

    attr_reader :template_type, :context

    def initialize(template_type, context = {})
      @template_type = template_type
      @context = context
    end

    def render
      erb_template.result(binding)
    end

    private

    def erb_template
      ERB.new(template_content, trim_mode: "-")
    end

    def template_content
      @template_content ||= File.read(template_file_path)
    end

    def template_file_path
      element_type = context[:detected_element_type] || "generic"
      
      # Try element-specific template first
      specific_path = TEMPLATE_PATH.join("#{template_type}", "#{element_type}.erb")
      return specific_path if File.exist?(specific_path)
      
      # Fall back to generic template
      generic_path = TEMPLATE_PATH.join("#{template_type}", "generic.erb")
      return generic_path if File.exist?(generic_path)
      
      raise TemplateNotFoundError, "No template found for #{template_type}/#{element_type}"
    end

    # Template helper methods available in ERB
    def format_examples(examples)
      examples.map.with_index(1) do |example, index|
        "Example #{index}:\n#{example[:input]}\n\nOutput:\n#{example[:output].to_json}\n"
      end.join("\n---\n\n")
    end

    def format_standards(standards)
      standards.map { |std| "- #{std[:name]}: #{std[:description]}" }.join("\n")
    end

    def format_rules(rules)
      rules.map { |rule| "• #{rule}" }.join("\n")
    end
  end

  class TemplateNotFoundError < StandardError; end
end
```

### 3. Element Type Detection
```ruby
# app/services/ai/element_type_detector.rb
module Ai
  class ElementTypeDetector
    ELEMENT_KEYWORDS = {
      wall: %w[wall partition cavity blockwork brickwork stud],
      door: %w[door doorway entrance exit opening],
      window: %w[window glazing casement sash opening],
      floor: %w[floor slab flooring decking],
      ceiling: %w[ceiling soffit overhead],
      roof: %w[roof roofing tiles slate membrane],
      foundation: %w[foundation footing pile basement],
      beam: %w[beam joist lintel header],
      column: %w[column post pillar support],
      stairs: %w[stair step flight landing],
      railing: %w[railing balustrade handrail guardrail],
      electrical: %w[electrical wiring cable lighting switch socket],
      plumbing: %w[plumbing pipe drainage water supply],
      hvac: %w[heating ventilation air conditioning ductwork]
    }.freeze

    attr_reader :element

    def initialize(element)
      @element = element
    end

    def detect
      # First try element.element_type if set
      return element.element_type if element.element_type.present?

      # Analyze element name
      name_type = analyze_text(element.name.downcase)
      return name_type if name_type

      # Analyze specification
      spec_type = analyze_text(element.specification.downcase)
      return spec_type if spec_type

      # Default fallback
      "wall"
    end

    def confidence_scores
      text = "#{element.name} #{element.specification}".downcase
      
      ELEMENT_KEYWORDS.transform_values do |keywords|
        matches = keywords.count { |keyword| text.include?(keyword) }
        keywords_weight = keywords.sum { |keyword| text.scan(keyword).length }
        
        # Calculate confidence based on keyword frequency and weight
        (matches + keywords_weight) / keywords.length.to_f
      end
    end

    def top_candidates(limit = 3)
      confidence_scores
        .sort_by { |_, score| -score }
        .first(limit)
        .to_h
    end

    private

    def analyze_text(text)
      max_score = 0
      detected_type = nil

      ELEMENT_KEYWORDS.each do |type, keywords|
        score = keywords.count { |keyword| text.include?(keyword) }
        
        if score > max_score
          max_score = score
          detected_type = type.to_s
        end
      end

      detected_type if max_score > 0
    end
  end
end
```

### 4. Regional Standards Configuration
```ruby
# app/services/ai/regional_standards.rb
module Ai
  class RegionalStandards
    STANDARDS = {
      "london" => {
        measurement_system: "metric",
        primary_standards: [
          { name: "NRM2", description: "New Rules of Measurement 2" },
          { name: "BS 8541", description: "Library of standardized method of measurement" },
          { name: "Building Regulations", description: "UK Building Regulations" }
        ],
        units: {
          length: "mm",
          area: "m²",
          volume: "m³",
          weight: "kg"
        },
        typical_materials: %w[brick block concrete steel timber],
        fire_ratings: %w[30min 60min 90min 120min],
        thermal_standards: "Part L Building Regulations"
      },
      "manchester" => {
        measurement_system: "metric",
        primary_standards: [
          { name: "NRM2", description: "New Rules of Measurement 2" },
          { name: "BS 8541", description: "Library of standardized method of measurement" },
          { name: "Building Regulations", description: "UK Building Regulations" }
        ],
        units: {
          length: "mm",
          area: "m²",
          volume: "m³",
          weight: "kg"
        },
        typical_materials: %w[brick block concrete steel timber],
        fire_ratings: %w[30min 60min 90min 120min],
        thermal_standards: "Part L Building Regulations"
      }
    }.freeze

    class << self
      def for_region(region)
        normalized_region = region.to_s.downcase
        STANDARDS[normalized_region] || default_standards
      end

      def supported_regions
        STANDARDS.keys
      end

      private

      def default_standards
        STANDARDS["london"] # UK standards as default
      end
    end
  end
end
```

### 5. Few-Shot Examples
```ruby
# app/services/ai/few_shot_examples.rb
module Ai
  class FewShotExamples
    EXAMPLES_PATH = Rails.root.join("config", "ai_examples")

    attr_reader :element_type, :region

    def initialize(element_type:, region:)
      @element_type = element_type
      @region = region
    end

    def examples
      @examples ||= load_examples
    end

    private

    def load_examples
      examples = []
      
      # Load element-specific examples
      element_file = EXAMPLES_PATH.join("#{element_type}.yml")
      if File.exist?(element_file)
        element_examples = YAML.load_file(element_file)
        examples.concat(element_examples["examples"] || [])
      end
      
      # Load regional examples
      regional_file = EXAMPLES_PATH.join("regions", "#{region.downcase}.yml")
      if File.exist?(regional_file)
        regional_examples = YAML.load_file(regional_file)
        examples.concat(regional_examples["examples"] || [])
      end
      
      # Load generic examples if none found
      if examples.empty?
        generic_file = EXAMPLES_PATH.join("generic.yml")
        if File.exist?(generic_file)
          generic_examples = YAML.load_file(generic_file)
          examples.concat(generic_examples["examples"] || [])
        end
      end
      
      # Limit and randomize examples
      examples.sample(3)
    end
  end
end
```

### 6. System Prompt Template
```erb
<!-- config/ai_prompts/system/wall.erb -->
You are a specialist construction specification analyst focusing on wall elements. Your expertise includes cavity walls, partition walls, structural walls, and cladding systems commonly used in <%= context[:project].region %> construction.

## Your Task
Analyze building specifications and extract structured data for wall elements. Focus on construction details, materials, dimensions, and performance characteristics specific to wall systems.

## Regional Context
- Project Location: <%= context[:project].region %>
- Applicable Standards: <%= format_standards(context[:regional_standards][:primary_standards]) %>
- Measurement System: <%= context[:regional_standards][:measurement_system] %>
- Standard Units: <%= context[:regional_standards][:units].map { |k,v| "#{k}: #{v}" }.join(", ") %>

## Wall-Specific Extraction Rules
<%= format_rules(context[:extraction_focus]) %>

## Expected Output Format
Return your analysis as valid JSON with this structure:
```json
{
  "element_type": "wall",
  "confidence": 0.95,
  "parameters": {
    "dimensions": {
      "length": 5000,
      "height": 2700,
      "thickness": 150
    },
    "construction": {
      "wall_type": "cavity_wall",
      "inner_leaf": "100mm concrete block",
      "outer_leaf": "102.5mm facing brick",
      "cavity_width": 75,
      "insulation": "75mm rigid foam",
      "ties": "stainless steel at 450mm centres"
    },
    "materials": {
      "structural": "concrete block",
      "facing": "facing brick",
      "insulation": "rigid foam",
      "mortar": "class II"
    },
    "finishes": {
      "internal": "12.5mm plasterboard, skim finish",
      "external": "facing brick, pointed"
    },
    "performance": {
      "fire_rating": "120min",
      "thermal_resistance": "3.5 m²K/W",
      "acoustic_rating": "45dB"
    },
    "location": {
      "elevation": "north",
      "building_zone": "external perimeter"
    }
  },
  "validation_flags": [
    {
      "type": "missing_data",
      "field": "thermal_resistance",
      "severity": "medium",
      "message": "Thermal performance not specified"
    }
  ],
  "notes": "Standard cavity wall construction suitable for residential/commercial use"
}
```

## Quality Guidelines
- Use <%= context[:regional_standards][:measurement_system] %> measurements in <%= context[:regional_standards][:units][:length] %>
- Reference applicable standards: <%= context[:regional_standards][:primary_standards].map { |s| s[:name] }.join(", ") %>
- Flag missing critical information
- Provide confidence score based on specification clarity
- Include validation flags for potential issues

<% if context[:few_shot_examples].any? %>
## Examples
<%= format_examples(context[:few_shot_examples]) %>
<% end %>

## Validation Rules
<%= format_rules(context[:validation_rules]) %>
```

### 7. User Prompt Template
```erb
<!-- config/ai_prompts/user/generic.erb -->
Analyze this construction specification and extract structured data:

**Project Context:**
- Project: <%= context[:project].title %>
- Client: <%= context[:project].client %>
- Location: <%= context[:project].address %>, <%= context[:project].region %>

**Element Details:**
- Element Name: <%= context[:element].name %>
- Element Type: <%= context[:detected_element_type].humanize %>

**Specification:**
<%= context[:element].specification %>

<% if context[:specification_complexity] > 0.7 %>
**Note:** This is a complex specification. Pay special attention to:
- Multiple materials or construction methods
- Performance requirements
- Interface details
- Special construction notes
<% end %>

Please extract all relevant information following the JSON format specified in the system prompt. Focus on:
1. Accurate dimensional extraction
2. Complete material identification
3. Construction method details
4. Performance characteristics
5. Any regional standard references

Ensure your confidence score reflects the clarity and completeness of the specification.
```

### 8. Specification Complexity Analyzer
```ruby
# app/services/ai/specification_complexity.rb
module Ai
  class SpecificationComplexity
    COMPLEXITY_INDICATORS = {
      multiple_materials: /\b(?:and|with|including|comprising)\b.*\b(?:and|with|including|comprising)\b/i,
      dimensions_mentioned: /\b\d+\.?\d*\s*(?:mm|m|cm|inches?|ft|feet)\b/i,
      performance_specs: /\b(?:fire|thermal|acoustic|structural|resistance|rating|class|grade)\b/i,
      standards_referenced: /\b(?:BS|EN|ISO|ASTM|NRM|building regulations?)\s*\d+/i,
      technical_terms: /\b(?:cavity|insulation|membrane|dpc|ties|fixings|flashings)\b/i,
      multiple_sentences: /[.!?]\s+[A-Z]/
    }.freeze

    attr_reader :specification

    def initialize(specification)
      @specification = specification.to_s
    end

    def score
      return 0.0 if specification.blank?

      total_weight = 0
      matched_weight = 0

      COMPLEXITY_INDICATORS.each do |indicator, pattern|
        weight = weight_for_indicator(indicator)
        total_weight += weight

        if specification.match?(pattern)
          matched_weight += weight
        end
      end

      # Add length-based complexity
      length_factor = [specification.length / 200.0, 1.0].min * 0.2
      
      base_score = matched_weight / total_weight.to_f
      final_score = base_score + length_factor

      [final_score, 1.0].min
    end

    def complexity_level
      case score
      when 0.0..0.3
        :simple
      when 0.3..0.6
        :moderate
      else
        :complex
      end
    end

    def analysis
      {
        score: score,
        level: complexity_level,
        indicators: matched_indicators,
        word_count: specification.split.length,
        sentence_count: specification.split(/[.!?]/).length
      }
    end

    private

    def weight_for_indicator(indicator)
      case indicator
      when :multiple_materials
        0.25
      when :dimensions_mentioned
        0.20
      when :performance_specs
        0.20
      when :standards_referenced
        0.15
      when :technical_terms
        0.15
      when :multiple_sentences
        0.05
      else
        0.10
      end
    end

    def matched_indicators
      COMPLEXITY_INDICATORS.select do |_, pattern|
        specification.match?(pattern)
      end.keys
    end
  end
end
```

### 9. Enhanced AI Specification Processor
```ruby
# Update app/services/ai/specification_processor.rb to use prompt engine

module Ai
  class SpecificationProcessor < BaseService
    # ... existing code ...

    private

    def build_messages
      prompt_engine = PromptEngine.new(@element)
      
      [
        {
          role: "system",
          content: prompt_engine.build_system_prompt
        },
        {
          role: "user", 
          content: prompt_engine.build_user_prompt
        }
      ]
    end

    # Remove old system_prompt and user_prompt methods
    # ... rest of existing code ...
  end
end
```

### 10. Example Configuration Files
```yaml
# config/ai_examples/wall.yml
examples:
  - input: "External wall comprising 100mm concrete blockwork inner leaf, 75mm rigid foam insulation, 50mm cavity, and 102.5mm facing brick outer leaf with stainless steel wall ties at 450mm centres."
    output:
      element_type: "wall"
      confidence: 0.95
      parameters:
        dimensions:
          thickness: 252.5
          cavity_width: 50
        construction:
          wall_type: "cavity_wall"
          inner_leaf: "100mm concrete block"
          outer_leaf: "102.5mm facing brick"
          insulation: "75mm rigid foam"
          ties: "stainless steel at 450mm centres"
        materials:
          structural: "concrete block"
          facing: "facing brick"
          insulation: "rigid foam"
      notes: "Standard cavity wall construction"

  - input: "100mm metal stud partition with 12.5mm plasterboard each side, taped and filled ready for decoration."
    output:
      element_type: "wall"
      confidence: 0.90
      parameters:
        dimensions:
          thickness: 125
        construction:
          wall_type: "partition"
          frame: "100mm metal stud"
          lining: "12.5mm plasterboard each side"
        finishes:
          internal: "taped and filled ready for decoration"
      notes: "Internal partition wall"
```

## Technical Notes
- Template-based prompts allow easy customization and versioning
- Element-type detection improves prompt relevance
- Regional standards ensure local compliance
- Few-shot examples improve extraction accuracy
- Complexity analysis helps adjust processing approach
- Validation rules catch common specification issues

## Definition of Done
- [ ] Element-specific prompt templates created
- [ ] Regional standards configuration implemented
- [ ] Few-shot example system working
- [ ] Element type detection accurate
- [ ] Complexity analysis functional
- [ ] Template rendering error-free
- [ ] Prompt versioning system ready
- [ ] Test coverage exceeds 90%
- [ ] Code review completed