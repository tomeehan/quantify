# Ticket 1: AI Service Integration

**Epic**: M3 AI Processing & Extraction  
**Story Points**: 5  
**Dependencies**: M-02 (Element model and processing pipeline)

## Description
Create the core AI service integration that processes building specifications and extracts structured data. This service handles LLM communication, prompt engineering, response parsing, and error handling for specification analysis.

## Acceptance Criteria
- [ ] AI service class with specification processing capabilities
- [ ] Configurable LLM provider integration (OpenAI, Anthropic, etc.)
- [ ] Robust prompt engineering for construction specification analysis
- [ ] Response parsing and validation
- [ ] Error handling and retry logic
- [ ] Comprehensive logging and monitoring
- [ ] Test coverage with mocked AI responses

## Code to be Written

### 1. AI Configuration
```ruby
# config/ai.yml
default: &default
  provider: openai
  max_tokens: 2000
  temperature: 0.1
  timeout: 30
  retry_attempts: 3
  retry_delay: 2

development:
  <<: *default
  api_key: <%= ENV.fetch("OPENAI_API_KEY", "test-key") %>
  model: gpt-4

test:
  <<: *default
  provider: mock
  api_key: test-key
  model: mock-model

staging:
  <<: *default
  api_key: <%= ENV.fetch("OPENAI_API_KEY") %>
  model: gpt-4

production:
  <<: *default
  api_key: <%= ENV.fetch("OPENAI_API_KEY") %>
  model: gpt-4
  timeout: 60
  max_tokens: 3000
```

### 2. AI Service Base Class
```ruby
# app/services/ai/base_service.rb
module Ai
  class BaseService
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :provider, :string, default: -> { Rails.application.config_for(:ai)["provider"] }
    attribute :api_key, :string, default: -> { Rails.application.config_for(:ai)["api_key"] }
    attribute :model, :string, default: -> { Rails.application.config_for(:ai)["model"] }
    attribute :max_tokens, :integer, default: -> { Rails.application.config_for(:ai)["max_tokens"] }
    attribute :temperature, :float, default: -> { Rails.application.config_for(:ai)["temperature"] }
    attribute :timeout, :integer, default: -> { Rails.application.config_for(:ai)["timeout"] }

    class << self
      def call(*args, **kwargs)
        new(*args, **kwargs).call
      end
    end

    def call
      raise NotImplementedError, "Subclasses must implement #call"
    end

    private

    def ai_config
      @ai_config ||= Rails.application.config_for(:ai)
    end

    def client
      @client ||= case provider.to_sym
                  when :openai
                    OpenAI::Client.new(access_token: api_key, request_timeout: timeout)
                  when :anthropic
                    Anthropic::Client.new(api_key: api_key, timeout: timeout)
                  when :mock
                    MockAiClient.new
                  else
                    raise ArgumentError, "Unsupported AI provider: #{provider}"
                  end
    end

    def log_request(prompt, context = {})
      Rails.logger.info("AI Request", {
        provider: provider,
        model: model,
        prompt_length: prompt.length,
        context: context
      })
    end

    def log_response(response, duration, context = {})
      Rails.logger.info("AI Response", {
        provider: provider,
        model: model,
        response_length: response.length,
        duration_ms: duration,
        context: context
      })
    end

    def log_error(error, context = {})
      Rails.logger.error("AI Error", {
        provider: provider,
        model: model,
        error: error.message,
        error_class: error.class.name,
        context: context
      })
    end

    def with_retries(max_attempts: ai_config["retry_attempts"], delay: ai_config["retry_delay"])
      attempt = 1
      
      begin
        yield
      rescue => error
        if attempt < max_attempts && retryable_error?(error)
          log_error(error, { attempt: attempt, retrying: true })
          sleep(delay * attempt)
          attempt += 1
          retry
        else
          log_error(error, { attempt: attempt, final: true })
          raise error
        end
      end
    end

    def retryable_error?(error)
      case error
      when Net::TimeoutError, Errno::ECONNREFUSED, Errno::ECONNRESET
        true
      when StandardError
        # Check for rate limiting or temporary server errors
        error.message.match?(/rate limit|quota|timeout|502|503|504/i)
      else
        false
      end
    end
  end
end
```

### 3. Specification Processor Service
```ruby
# app/services/ai/specification_processor.rb
module Ai
  class SpecificationProcessor < BaseService
    attr_reader :element, :specification

    def initialize(element)
      super()
      @element = element
      @specification = element.specification
    end

    def call
      start_time = Time.current
      context = { element_id: element.id, project_id: element.project.id }
      
      log_request(specification, context)
      
      response = with_retries do
        case provider.to_sym
        when :openai
          process_with_openai
        when :anthropic
          process_with_anthropic
        when :mock
          process_with_mock
        else
          raise ArgumentError, "Unsupported provider: #{provider}"
        end
      end
      
      duration = ((Time.current - start_time) * 1000).round
      log_response(response.to_s, duration, context)
      
      parse_response(response)
      
    rescue => error
      log_error(error, context)
      raise Ai::ProcessingError.new(error.message, element: element)
    end

    private

    def process_with_openai
      response = client.chat(
        parameters: {
          model: model,
          messages: build_messages,
          max_tokens: max_tokens,
          temperature: temperature,
          response_format: { type: "json_object" }
        }
      )
      
      response.dig("choices", 0, "message", "content")
    end

    def process_with_anthropic
      response = client.messages(
        model: model,
        max_tokens: max_tokens,
        temperature: temperature,
        messages: build_messages
      )
      
      response.dig("content", 0, "text")
    end

    def process_with_mock
      MockAiResponse.new(element).generate
    end

    def build_messages
      [
        {
          role: "system",
          content: system_prompt
        },
        {
          role: "user",
          content: user_prompt
        }
      ]
    end

    def system_prompt
      <<~PROMPT
        You are a construction specification analysis expert. Your task is to extract structured data from building specifications and classify construction elements.

        Analyze the provided specification and extract the following information:
        1. Element type (wall, door, window, floor, ceiling, roof, foundation, beam, column, slab, stairs, railing, fixture, electrical, plumbing, hvac)
        2. Dimensions (length, width, height, thickness, diameter, etc.)
        3. Materials and finishes
        4. Construction details and methods
        5. Location information
        6. Performance requirements (fire rating, thermal properties, etc.)

        Return your analysis in valid JSON format with this structure:
        {
          "element_type": "string",
          "confidence": 0.95,
          "parameters": {
            "dimensions": {},
            "materials": {},
            "finishes": {},
            "details": {},
            "location": {},
            "performance": {}
          },
          "notes": "Any additional observations or uncertainties"
        }

        Rules:
        - Use metric units (mm, m, kg, etc.)
        - Extract only information explicitly stated in the specification
        - Set confidence between 0.0 and 1.0 based on clarity of specification
        - Include specific product names, standards, or codes mentioned
        - Note any ambiguities or missing information in the notes field
      PROMPT
    end

    def user_prompt
      <<~PROMPT
        Analyze this construction specification:

        Element Name: #{element.name}
        Project: #{element.project.title} (#{element.project.region})

        Specification:
        #{specification}

        Extract the structured data as JSON following the format provided in the system prompt.
      PROMPT
    end

    def parse_response(response_text)
      begin
        response = JSON.parse(response_text)
        
        validate_response_structure(response)
        
        {
          element_type: response["element_type"],
          confidence: response["confidence"].to_f,
          extracted_params: response["parameters"] || {},
          notes: response["notes"]
        }
        
      rescue JSON::ParserError => e
        raise Ai::ParseError.new("Invalid JSON response: #{e.message}", response: response_text)
      rescue => e
        raise Ai::ParseError.new("Response parsing failed: #{e.message}", response: response_text)
      end
    end

    def validate_response_structure(response)
      required_keys = %w[element_type confidence parameters]
      missing_keys = required_keys - response.keys
      
      if missing_keys.any?
        raise Ai::ParseError.new("Missing required keys: #{missing_keys.join(', ')}")
      end
      
      unless response["confidence"].is_a?(Numeric) && 
             response["confidence"] >= 0 && 
             response["confidence"] <= 1
        raise Ai::ParseError.new("Invalid confidence value: #{response['confidence']}")
      end
      
      unless response["parameters"].is_a?(Hash)
        raise Ai::ParseError.new("Parameters must be a hash")
      end
    end
  end
end
```

### 4. Custom Error Classes
```ruby
# app/services/ai/errors.rb
module Ai
  class BaseError < StandardError
    attr_reader :context

    def initialize(message, **context)
      super(message)
      @context = context
    end
  end

  class ProcessingError < BaseError
    attr_reader :element

    def initialize(message, element: nil, **context)
      super(message, **context)
      @element = element
    end
  end

  class ParseError < BaseError
    attr_reader :response

    def initialize(message, response: nil, **context)
      super(message, **context)
      @response = response
    end
  end

  class ConfigurationError < BaseError; end
  class RateLimitError < BaseError; end
  class QuotaExceededError < BaseError; end
end
```

### 5. Mock Client for Testing
```ruby
# app/services/ai/mock_ai_client.rb
module Ai
  class MockAiClient
    def chat(parameters:)
      {
        "choices" => [
          {
            "message" => {
              "content" => MockAiResponse.new(nil).generate
            }
          }
        ]
      }
    end

    def messages(*)
      {
        "content" => [
          {
            "text" => MockAiResponse.new(nil).generate
          }
        ]
      }
    end
  end

  class MockAiResponse
    attr_reader :element

    def initialize(element)
      @element = element
    end

    def generate
      {
        element_type: determine_mock_type,
        confidence: rand(0.7..0.98).round(2),
        parameters: generate_mock_parameters,
        notes: "Mock AI analysis for testing purposes"
      }.to_json
    end

    private

    def determine_mock_type
      return "wall" unless element&.specification

      spec = element.specification.downcase
      case spec
      when /door/
        "door"
      when /window/
        "window"
      when /wall/
        "wall"
      when /floor/, /slab/
        "floor"
      when /ceiling/
        "ceiling"
      when /roof/
        "roof"
      else
        "wall"
      end
    end

    def generate_mock_parameters
      {
        dimensions: {
          length: rand(1000..10000),
          width: rand(100..500),
          height: rand(2000..4000)
        },
        materials: {
          primary: "concrete",
          secondary: "steel"
        },
        finishes: {
          internal: "plaster",
          external: "brick"
        },
        details: {
          construction_method: "cavity_wall",
          insulation_type: "rigid_foam"
        },
        performance: {
          fire_rating: "120min",
          thermal_rating: "0.35"
        }
      }
    end
  end
end
```

### 6. Service Integration Tests
```ruby
# test/services/ai/specification_processor_test.rb
require "test_helper"

class Ai::SpecificationProcessorTest < ActiveSupport::TestCase
  setup do
    @element = elements(:external_wall)
    @processor = Ai::SpecificationProcessor.new(@element)
  end

  test "should process specification successfully" do
    result = @processor.call
    
    assert result.is_a?(Hash)
    assert result.key?(:element_type)
    assert result.key?(:confidence)
    assert result.key?(:extracted_params)
    assert result.key?(:notes)
  end

  test "should validate confidence score range" do
    result = @processor.call
    
    assert result[:confidence] >= 0.0
    assert result[:confidence] <= 1.0
  end

  test "should extract parameters as hash" do
    result = @processor.call
    
    assert result[:extracted_params].is_a?(Hash)
  end

  test "should handle empty specification" do
    @element.specification = ""
    
    assert_raises(Ai::ProcessingError) do
      @processor.call
    end
  end

  test "should handle invalid JSON response" do
    # Mock invalid response
    mock_client = Minitest::Mock.new
    mock_client.expect(:chat, { "choices" => [{ "message" => { "content" => "invalid json" } }] }, [Hash])
    
    @processor.stub(:client, mock_client) do
      assert_raises(Ai::ParseError) do
        @processor.call
      end
    end
  end

  test "should retry on network errors" do
    attempt_count = 0
    mock_client = Minitest::Mock.new
    
    @processor.stub(:client, mock_client) do
      @processor.stub(:process_with_openai, -> {
        attempt_count += 1
        if attempt_count < 3
          raise Net::TimeoutError.new("Connection timeout")
        else
          '{"element_type": "wall", "confidence": 0.9, "parameters": {}, "notes": "success"}'
        end
      }) do
        result = @processor.call
        assert_equal 3, attempt_count
        assert_equal "wall", result[:element_type]
      end
    end
  end

  test "should log processing requests and responses" do
    logs = []
    Rails.logger.stub(:info, ->(msg, data = {}) { logs << { level: :info, message: msg, data: data } }) do
      @processor.call
    end
    
    request_log = logs.find { |log| log[:message] == "AI Request" }
    response_log = logs.find { |log| log[:message] == "AI Response" }
    
    assert request_log
    assert response_log
    assert request_log[:data][:element_id] == @element.id
  end
end
```

### 7. Configuration Initializer
```ruby
# config/initializers/ai.rb
begin
  ai_config = Rails.application.config_for(:ai)
  
  # Validate required configuration
  required_keys = %w[provider api_key model]
  missing_keys = required_keys.select { |key| ai_config[key].blank? }
  
  if missing_keys.any? && !Rails.env.test?
    raise Ai::ConfigurationError.new("Missing AI configuration: #{missing_keys.join(', ')}")
  end
  
  Rails.logger.info("AI Service initialized", {
    provider: ai_config["provider"],
    model: ai_config["model"],
    environment: Rails.env
  })
  
rescue => e
  Rails.logger.error("AI Service initialization failed: #{e.message}")
  raise e unless Rails.env.development? || Rails.env.test?
end
```

## Technical Notes
- Supports multiple AI providers with consistent interface
- Implements robust error handling and retry logic
- Uses structured prompts for consistent extraction
- Includes comprehensive logging for monitoring
- Mock implementation for testing without API calls
- JSON response format ensures structured data extraction

## Definition of Done
- [ ] AI service processes specifications successfully
- [ ] Multiple provider support implemented
- [ ] Error handling covers all scenarios
- [ ] Retry logic works for transient failures
- [ ] Mock client enables testing without API calls
- [ ] Logging provides sufficient debugging information
- [ ] Configuration validation prevents startup issues
- [ ] Test coverage exceeds 90%
- [ ] Code review completed