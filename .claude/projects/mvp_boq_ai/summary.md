# MVP BoQ AI Complete System

**Project URL**: https://linear.app/quantify-ai/project/mvp-boq-ai-engine-b405328c1086

## Overview
Complete MVP BoQ AI system combining both the web application interface and the underlying engine. Delivers an end-to-end solution for contractors, estimators, and quantity surveyors to generate Bills of Quantities through AI-powered specification processing.

## What the System Does
The MVP BoQ AI system transforms unstructured construction specifications into accurate, priced Bills of Quantities through this workflow:

**1. Project Creation**
- User authentication and account management (leveraging Jumpstart Pro multi-tenancy)
- Project creation with client, title, address, and region selection

**2. Specification Input**
- Free-text specification entry for building elements in natural language
- Support for complex, multi-line construction specifications
- Raw specification capture exactly as user provides it

**3. AI Processing & Extraction**
- LLM processes specifications and extracts structured data
- Identifies: Type, Deflection/Dimensions, Wall type, Material, Finish, Location, Details
- Displays extracted elements in structured format for review

**4. LLM Element Data Verification**
- User reviews and confirms AI-extracted information
- Inline editing capability for corrections or additions
- Tracks confidence levels and data sources (AI vs user-confirmed)

**5. NRM Database Integration**
- LLM suggests appropriate NRM (New Rules of Measurement) codes
- Integration with external NRM database for rates and rules
- Generates clarification questions when data is incomplete

**6. Question Resolution & Parameter Collection**
- Interactive Q&A interface for missing parameters
- Progressive disclosure - only asks necessary questions
- Dynamic forms based on NRM requirements and element type

**7. Quantity Calculation & Assembly Processing**
- LLM applies appropriate assembly calculation formulas
- Deterministic quantity calculation with transparent methodology
- Multiple quantity types per element (area, volume, linear measurements)

**8. Rate Application & Integration**
- Integration with external relational rate database
- Automatic rate matching based on NRM codes and project region
- Application of current market rates (Labour, Plant, Material)

**9. BoQ Line Generation**
- Complete priced Bill of Quantities with line-by-line calculations
- Project-level totals and comprehensive audit trail
- Real-time updates and error handling

**10. Export & Snapshot Management**
- Professional Excel/PDF export capabilities
- Historical snapshot preservation for audit compliance
- Multiple export formats and delivery options

## Data Architecture

**Core Models**
- **Project**: Container for client, title, address, region metadata
- **Element**: User specifications with NRM codes and physical parameters  
- **NrmItems**: Reference data for NRM classification codes and unit rules
- **Assembly**: Calculation formulas with input schemas and measurement units
- **Quantity**: Calculated values linking elements to assemblies
- **Rate**: Regional pricing data categorized by type (Labour, Plant, Material)
- **BoqLine**: Final priced lines with quantity, rate, total, and source audit data

**Relationships**
- Project → has many Elements
- Element → belongs to Project, has many Quantities
- NrmItems → has many Assemblies
- Assembly → has many Quantities
- Quantity → belongs to Element and Assembly, has many BoqLines
- Rate → has many BoqLines
- BoqLine → belongs to Quantity and Rate

## Technology Stack
- **Rails 8.0**: Core application framework with Hotwire/Turbo for reactive UI
- **PostgreSQL**: Primary database for all domain models and relationships
- **Jumpstart Pro**: Multi-tenant SaaS foundation with authentication and billing
- **LLM Integration**: External AI services for specification processing
- **External Rate DB**: Integration point for current regional pricing data
- **JSON Schema**: Input validation and parameter collection system
- **Background Jobs**: SolidQueue for asynchronous AI and calculation workflows
- **Export Libraries**: PDF/Excel generation for BoQ output formats

## MVP Milestones (User-Value Prioritized)

### Phase 1: Core Project & Specification Input (Week 1-2)
**M1.1: Basic Project Creation**
- Project model with client, title, address, region fields
- Simple project creation form leveraging Jumpstart Pro account system
- Project dashboard showing created projects
- *User value: Can start organizing their BoQ work*

**M1.2: Element Specification Input**
- Element model with project association, name, and raw specification text
- Add element form with textarea for free-text specs
- Element list view showing specifications for a project
- *User value: Can input their building specifications*

### Phase 2: AI Processing & NRM Suggestions (Week 3-4)
**M2.1: Mock AI Processing**
- NrmItems model with basic construction codes
- Static NRM suggestions based on keyword matching
- Display suggested NRM codes for each element
- Allow user to accept/reject suggestions
- *User value: Gets immediate NRM guidance (even if simplified)*

**M2.2: Real LLM Integration**
- Integrate with external LLM service for specification analysis
- Extract dimensions, materials, construction details
- Populate element params field with extracted data
- Background job processing for AI calls
- *User value: AI actually understands their specifications*

### Phase 3: Parameter Collection & Clarification (Week 5-6)
**M3.1: Basic Parameter Forms**
- Simple forms for common parameters (length, width, height)
- Save parameters to element.params JSON field
- Display collected parameters in element view
- *User value: Can input missing measurements*

**M3.2: Dynamic Clarification System**
- Assembly model with inputs_schema for parameter requirements
- Generate clarification questions based on missing assembly inputs
- Interactive Q&A interface for parameter collection
- Progressive parameter completion tracking
- *User value: System guides them to complete specifications*

### Phase 4: Quantity Calculation (Week 7-8)
**M4.1: Assembly & Quantity Models**
- Assembly model with formula, inputs_schema, unit
- Quantity model linking elements to assemblies
- Seed basic assemblies for common construction elements
- *User value: Foundation for quantity calculations*

**M4.2: Basic Quantity Calculator**
- Simple formula evaluation engine for basic assemblies (area, volume)
- Display calculated quantities for elements
- Show calculation breakdown and assumptions
- *User value: Gets actual quantities for their elements*

### Phase 5: Rate Application & Pricing (Week 9-10)
**M5.1: Rate Model & Basic Pricing**
- Rate model with type, unit, rate_per_unit
- Seed basic regional rates for common items
- Apply rates to quantities to generate line totals
- *User value: Gets priced BoQ lines*

**M5.2: BoQ Line Generation**
- BoqLine model with quantity, rate, total, audit trail
- Generate complete BoQ with all calculated lines
- Display formatted BoQ table with totals
- *User value: Complete priced Bill of Quantities*

### Phase 6: Export & Snapshots (Week 11-12)
**M6.1: Basic Export**
- Export BoQ to Excel/CSV format
- Include quantities, rates, totals, descriptions
- Download functionality
- *User value: Can share BoQ with colleagues/clients*

**M6.2: Snapshot Management**
- Save BoQ snapshots with frozen rates and calculations
- Snapshot history view
- Compare snapshots functionality
- *User value: Historical record for audit/comparison*

## Business Context
Traditional BoQ production is slow, manual, and error-prone. This MVP system streamlines the entire workflow by combining AI interpretation with deterministic calculations, giving construction firms a competitive advantage in tendering processes.

The system reduces adoption friction by providing familiar outputs (standard BoQ formats) while automating the complex analysis and calculation steps that typically require specialized quantity surveying expertise.

## Success Metrics
- Time reduction: 80% faster BoQ generation vs manual methods
- Accuracy improvement: Consistent calculations with full audit trails
- User adoption: QS teams can use without specialized training
- Export compatibility: BoQs integrate with existing estimating workflows

## Status
MVP Development Phase - Ready for implementation