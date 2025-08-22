# MVP BoQ AI Milestones
*Based on Updated User Flow Diagram*

## Linear Project Structure
These milestones should be created as individual issues in Linear with the following labels:
- `priority:critical` for M1-M3 (core user journey)
- `priority:high` for M4-M6 (AI processing workflow)
- `priority:medium` for M7-M9 (calculation & pricing)
- `priority:low` for M10-M12 (export & snapshots)

---

## M1: Project Creation
**Epic**: Foundation  
**Story Points**: 5  
**Dependencies**: None  
**User Value**: Can organize BoQ work by project

**Acceptance Criteria**:
- [ ] Project model with fields: client, title, address, region
- [ ] Project creation form with validation
- [ ] Project dashboard showing user's projects (scoped by current_account)
- [ ] Project show page with basic navigation
- [ ] Pundit policy for project authorization

**Technical Notes**:
- Leverage Jumpstart Pro account/user system
- Follow existing model patterns
- Use Hotwire for form interactions

---

## M2: Specification Input
**Epic**: Specification Capture  
**Story Points**: 8  
**Dependencies**: M1  
**User Value**: Can input building specifications in natural language

**Acceptance Criteria**:
- [ ] Element model with fields: project_id, name, specification_text
- [ ] "Add specification" form with textarea for natural language input
- [ ] Specification list view showing all project specifications
- [ ] Edit/delete specification functionality
- [ ] Character count and validation
- [ ] Support for multi-line complex specifications

**Technical Notes**:
- Use `text` field type for large specifications
- Stimulus controller for dynamic form behavior
- Store raw specification text exactly as user enters it

---

## M3: AI Processing & Extraction
**Epic**: AI Magic  
**Story Points**: 21  
**Dependencies**: M2  
**User Value**: AI understands specifications and extracts key information

**Acceptance Criteria**:
- [ ] LLM service integration (OpenAI/Anthropic API)
- [ ] Background job processes specifications on save
- [ ] Extract structured data: Type, Deflection/Dimension, Wall type, Material, Finish etc.
- [ ] Display extracted elements in structured format (as shown in diagram)
- [ ] Processing status indicators and progress feedback
- [ ] Error handling for API failures and retry logic

**Technical Notes**:
- Use SolidQueue for background AI processing
- Store AI responses in element.ai_analysis JSON field
- Create extraction display component matching diagram format
- Add rate limiting and cost controls for AI calls

---

## M4: LLM Element Data Verification
**Epic**: Data Verification  
**Story Points**: 13  
**Dependencies**: M3  
**User Value**: Can review and confirm AI-extracted information

**Acceptance Criteria**:
- [ ] Display AI-extracted data in editable form
- [ ] User can modify extracted Type, Dimensions, Materials, etc.
- [ ] Highlight confidence levels or uncertain extractions
- [ ] Save user corrections and confirmations
- [ ] Track which data is AI-extracted vs user-confirmed
- [ ] Bulk edit capabilities for similar elements

**Technical Notes**:
- JSON field for storing user confirmations/overrides
- Stimulus controllers for inline editing
- Visual indicators for data source (AI vs user)

---

## M5: NRM Database Integration & Clarification
**Epic**: NRM Processing  
**Story Points**: 18  
**Dependencies**: M4  
**User Value**: Gets expert NRM guidance and fills in missing details

**Acceptance Criteria**:
- [ ] NrmItems model with comprehensive NRM database
- [ ] LLM suggests appropriate NRM codes based on verified element data
- [ ] Integration with external NRM DB for rates and rules
- [ ] Clarification questions generated when data is incomplete
- [ ] Interactive Q&A interface for missing parameters
- [ ] Save responses and link to NRM items

**Technical Notes**:
- Seed comprehensive NRM database
- Background job for NRM code suggestion
- Dynamic question generation based on NRM requirements
- Store clarification responses in structured format

---

## M6: Question Resolution & Parameter Collection
**Epic**: Interactive Clarification  
**Story Points**: 13  
**Dependencies**: M5  
**User Value**: System guides completion of missing information

**Acceptance Criteria**:
- [ ] Dynamic question forms based on NRM requirements
- [ ] Progressive disclosure - only ask necessary questions
- [ ] Save answers and automatically proceed to next question
- [ ] Progress tracking showing completion status
- [ ] Support for different question types (text, numeric, selection)
- [ ] Return to previous questions if needed

**Technical Notes**:
- JSON schema for question definitions
- Stimulus controller for progressive question flow
- Store answers in structured element.params field

---

## M7: Quantity Calculation & Assembly Processing
**Epic**: Quantity Engine  
**Story Points**: 18  
**Dependencies**: M6  
**User Value**: Gets accurate calculated quantities

**Acceptance Criteria**:
- [ ] Assembly model with calculation formulas
- [ ] Quantity model linking elements to assemblies
- [ ] LLM applies appropriate assembly calculations
- [ ] Display calculated quantities with units
- [ ] Show calculation breakdown and methodology
- [ ] Handle multiple quantity types per element (area, volume, linear)

**Technical Notes**:
- Safe formula evaluation engine
- Store calculation audit trail
- Background job for complex calculations
- Real-time updates via Hotwire

---

## M8: Rate Application & Relational DB Integration
**Epic**: Pricing Engine  
**Story Points**: 15  
**Dependencies**: M7  
**User Value**: Gets current market rates applied to quantities

**Acceptance Criteria**:
- [ ] Rate model with regional pricing data
- [ ] Integration with external relational rate database
- [ ] Automatic rate matching based on NRM codes and region
- [ ] Apply rates to calculated quantities
- [ ] Handle multiple rate types (Labour, Plant, Material)
- [ ] Rate update mechanisms and version control

**Technical Notes**:
- External DB integration for current rates
- Rate caching and update strategies
- Regional rate filtering based on project location

---

## M9: BoQ Line Generation & Final Calculations
**Epic**: BoQ Assembly  
**Story Points**: 13  
**Dependencies**: M8  
**User Value**: Complete priced Bill of Quantities

**Acceptance Criteria**:
- [ ] BoqLine model with quantity, rate, total calculations
- [ ] Generate complete BoQ with all priced lines
- [ ] Project-level totals and summaries
- [ ] Line-by-line audit trail showing calculation source
- [ ] Handle missing rates and pricing exceptions
- [ ] Real-time total updates

**Technical Notes**:
- Store complete calculation chain in audit fields
- Efficient total calculation and caching
- Handle edge cases and missing data gracefully

---

## M10: Excel Export
**Epic**: Export Functionality  
**Story Points**: 8  
**Dependencies**: M9  
**User Value**: Can export BoQ to share with colleagues/clients

**Acceptance Criteria**:
- [ ] Export complete BoQ to Excel format (.xlsx)
- [ ] Professional formatting matching industry standards
- [ ] Include project metadata, assumptions, and audit trail
- [ ] Download functionality with progress indicators
- [ ] Handle large BoQs efficiently
- [ ] Multiple export templates/formats

**Technical Notes**:
- Use rubyXL or axlsx gem for Excel generation
- Background job for large exports
- Template system for different export formats

---

## M11: Snapshot Management & Historical Preservation
**Epic**: Historical Preservation  
**Story Points**: 13  
**Dependencies**: M10  
**User Value**: Can save pricing snapshots for audit and comparison

**Acceptance Criteria**:
- [ ] Save complete BoQ snapshots with frozen calculations
- [ ] Snapshot model stores immutable project state
- [ ] Snapshot history view with timestamps and metadata
- [ ] Compare snapshots to see pricing changes
- [ ] Restore or reference historical snapshots
- [ ] Snapshot annotations and notes

**Technical Notes**:
- JSON snapshot of complete project state
- Immutable snapshot records
- Efficient diff calculation for comparisons
- Background job for snapshot generation

---

## M12: User Export & Final BoQ
**Epic**: Final Delivery  
**Story Points**: 5  
**Dependencies**: M11  
**User Value**: Complete professional BoQ ready for use

**Acceptance Criteria**:
- [ ] Final BoQ export with all professional formatting
- [ ] Include cover page with project details
- [ ] Comprehensive audit trail and assumptions
- [ ] Multiple format options (PDF, Excel, CSV)
- [ ] Email delivery options
- [ ] Print-ready formatting

**Technical Notes**:
- PDF generation for professional documents
- Template system for different output formats
- Email integration for delivery

## Implementation Strategy

### Phase 1: Core Journey (M1-M3)
Focus on getting users through the basic input → AI processing workflow

### Phase 2: AI Workflow (M4-M6) 
Complete the AI-driven specification processing and clarification loop

### Phase 3: Calculation Engine (M7-M9)
Build the quantity calculation and pricing engine

### Phase 4: Export & Management (M10-M12)
Add professional export and historical management features

### Success Criteria
Each milestone should provide immediate user value and be demonstrable. Users should see progress at every step of their workflow.