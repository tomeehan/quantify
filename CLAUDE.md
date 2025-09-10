# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Jumpstart Pro Rails is a commercial multi-tenant SaaS starter application built with Rails 8.0. It provides subscription billing, team management, authentication, and modern Rails patterns for building subscription-based web applications.

## Development Commands

```bash
# Initial setup
bin/setup                    # Install dependencies and setup database

# Development server
bin/dev                      # Start development server with Overmind (includes Rails server, asset watching)
bin/rails server            # Standard Rails server only

# Database
bin/rails db:prepare         # Setup database (creates, migrates, seeds)
bin/rails db:migrate         # Run migrations
bin/rails db:seed           # Seed database

# Testing
bin/rails test              # Run test suite (Minitest)
bin/rails test:system       # Run system tests (Capybara + Selenium)

# Code quality
bin/rubocop                 # Run RuboCop linter (configured in .rubocop.yml)
bin/rubocop -a              # Auto-fix RuboCop issues

# Background jobs
bin/jobs                    # Start SolidQueue worker (if using SolidQueue)
bundle exec sidekiq         # Start Sidekiq worker (if using Sidekiq)
```

## Architecture

### Multi-tenancy System
- **Account-based tenancy**: Users belong to Accounts (personal or team)
- **AccountUser model**: Join table managing user-account relationships with roles
- **Current account switching**: Users can switch between accounts via `switch_account(account)`
- **Authorization**: Pundit policies scope data by current account

### Modular Models
Models use Ruby modules for organization:
```ruby
# app/models/user.rb
class User < ApplicationRecord
  include Accounts, Agreements, Authenticatable, Mentions, Notifiable, Searchable, Theme
end

# app/models/account.rb  
class Account < ApplicationRecord
  include Billing, Domains, Transfer, Types
end
```

### Jumpstart Configuration System
- **Dynamic configuration**: `config/jumpstart.yml` controls enabled features
- **Runtime gem loading**: `Gemfile.jumpstart` loads gems based on configuration
- **Feature toggles**: Payment processors, integrations, background jobs, etc.
- Access via `Jumpstart.config.payment_processors`, `Jumpstart.config.stripe?`, etc.

### Payment Architecture
- **Pay gem (~11.0)**: Unified interface for multiple payment processors
- **Processor-agnostic**: Stripe, Paddle, Braintree, PayPal, Lemon Squeezy support
- **Per-seat billing**: Team accounts with usage-based pricing
- **Subscription management**: In `app/models/account/billing.rb`

## Technology Stack

- **Rails 8.0** with Hotwire (Turbo + Stimulus)
- **PostgreSQL** (primary), **SolidQueue** (jobs), **SolidCache** (cache)
- **Import Maps** for JavaScript (no Node.js dependency)
- **TailwindCSS v4** via tailwindcss-rails gem
- **Devise** for authentication with custom extensions
- **Pundit** for authorization
- **Minitest** for testing with parallel execution

## Testing

- **Minitest** with fixtures in `test/fixtures/`
- **System tests** use Capybara with Selenium WebDriver
- **Test parallelization** enabled via `parallelize(workers: :number_of_processors)`
- **WebMock** configured to disable external HTTP requests
- **Test database** reset between runs

## Routes Organization

Routes are modularized in `config/routes/`:
- `accounts.rb` - Account management, switching, invitations
- `billing.rb` - Subscription, payment, receipt routes
- `users.rb` - User profile, settings, authentication
- `api.rb` - API v1 endpoints with JWT authentication

## Key Directories

- `app/controllers/accounts/` - Account-scoped controllers
- `app/models/concerns/` - Shared model modules
- `app/policies/` - Pundit authorization policies
- `lib/jumpstart/` - Core Jumpstart engine and configuration
- `config/routes/` - Modular route definitions
- `app/components/` - View components for reusable UI

## BoQ AI Application Architecture

### BoQ AI Data Model
The BoQ (Bill of Quantities) AI system uses the following core domain models:

**Project**
- `client` - Client name/organization
- `title` - Project title
- `address` - Project location
- `region` - Geographic region for rate application

**Element**
- `project` - Associated project
- `nrm_code` - New Rules of Measurement code
- `name` - Element description
- `params` - Physical parameters (length/width/height)

**NrmItems**
- `nrm_code` - NRM classification code
- `title` - NRM item description
- `unit_rule` - Measurement unit rules

**Assembly**
- `nrm_item` - Reference to NRM item
- `formula` - Calculation formula for quantities
- `inputs_schema` - JSON schema for required inputs
- `unit` - Measurement unit

**Quantity**
- `element` - Associated element
- `assembly` - Calculation assembly used
- `quantity` - Calculated quantity value
- `unit` - Measurement unit

**Rate**
- `type` - Rate category (Labour, Plant, Material)
- `unit` - Pricing unit
- `rate_per_unit` - Unit rate value

**BoqLine**
- `quantity` - Reference to quantity calculation
- `rate` - Applied unit rate
- `total` - Extended line total
- `source_json` - Audit trail data

### BoQ AI User and Data Flow

The application follows this user workflow:

1. **Authentication & Project Setup**
   - User logs in to the system
   - Creates a new project with client, title, address, region

2. **Element Specification**
   - User adds specification text for building elements
   - Supports natural language descriptions (e.g., "concrete slab", "brick wall", etc.)

3. **AI Processing** 
   - LLM processes user specifications and extracts key information
   - System identifies relevant NRM codes and assemblies
   - AI analyzes specifications for type, dimensions, materials, finishes

4. **Clarification Loop**
   - System identifies missing parameters needed for quantity calculations
   - Presents clarification questions to user (e.g., "What type of reinforcement?")
   - User provides additional parameters through forms

5. **Quantity Calculation**
   - LLM applies assembly formulas using confirmed parameters
   - Calculates quantities deterministically from assembly rules
   - Links to external Rate DB for current pricing

6. **Rate Application**
   - System applies regional rates from Rate DB
   - Calculates line totals (quantity × rate)
   - Maintains audit trail of all calculations

7. **BoQ Generation**
   - User can export complete BoQ to various formats
   - Generates snapshot for historical record
   - Provides detailed quantity breakdown with assumptions

### Key Components

- **LLM Integration**: AI-powered specification parsing and NRM code suggestion
- **Rate DB**: External database providing current regional unit rates
- **Assembly Engine**: Deterministic quantity calculation using stored formulas
- **Clarification System**: Interactive parameter collection for missing data
- **Snapshot Management**: Historical BoQ preservation for audit purposes

## Development Notes

- **Current account** available via `current_account` helper in controllers/views
- **Account switching** via `switch_account(account)` in tests
- **Billing features** conditionally loaded based on `Jumpstart.config.payments_enabled?`
- **Background jobs** configurable between SolidQueue and Sidekiq
- **Multi-database** setup with separate databases for cache, jobs, and cable