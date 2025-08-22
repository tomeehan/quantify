# Ticket 3: Create Element Views

**Epic**: M2 Specification Input  
**Story Points**: 4  
**Dependencies**: 002-elements-controller.md

## Description
Create comprehensive views for the Elements interface within projects. Views should provide an intuitive specification input experience, real-time processing status updates, and parameter editing capabilities. Design should follow Jumpstart Pro patterns with TailwindCSS styling and Hotwire integration.

## Acceptance Criteria
- [ ] Elements index with project context and status overview
- [ ] Element detail view with specification and parameters
- [ ] New/Edit forms with rich text input and validation display
- [ ] Real-time status updates during AI processing
- [ ] Parameter editing interface for user corrections
- [ ] Responsive design for desktop and mobile
- [ ] Bulk operations interface

## Code to be Written

### 1. Elements Index View
```erb
<!-- app/views/projects/elements/index.html.erb -->
<% content_for :title, "#{@project.title} - Elements" %>

<div class="min-h-screen bg-gray-50">
  <!-- Header -->
  <div class="bg-white shadow">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
      <div class="flex items-center justify-between py-6">
        <div class="flex items-center space-x-4">
          <%= link_to @project, class: "text-gray-400 hover:text-gray-600" do %>
            <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
            </svg>
          <% end %>
          <div>
            <h1 class="text-2xl font-bold text-gray-900">Elements</h1>
            <p class="text-sm text-gray-500">
              <%= link_to @project.title, @project, class: "hover:text-gray-700" %> • 
              <%= pluralize(@project.elements.count, 'element') %>
            </p>
          </div>
        </div>
        
        <div class="flex items-center space-x-3">
          <% if @project.elements.needs_processing.any? %>
            <%= link_to "Process All", bulk_process_project_elements_path(@project),
                method: :patch,
                class: "btn btn-secondary",
                data: { 
                  turbo_method: :patch,
                  turbo_confirm: "Process #{@pending_count} pending elements?" 
                } %>
          <% end %>
          <%= link_to "Add Element", new_project_element_path(@project), 
              class: "btn btn-primary",
              data: { turbo_frame: "modal" } %>
        </div>
      </div>
    </div>
  </div>

  <!-- Status Summary -->
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
    <div class="grid grid-cols-1 gap-5 sm:grid-cols-4">
      <div class="bg-white overflow-hidden shadow rounded-lg">
        <div class="p-5">
          <div class="flex items-center">
            <div class="flex-shrink-0">
              <div class="w-8 h-8 bg-yellow-100 rounded-full flex items-center justify-center">
                <svg class="w-5 h-5 text-yellow-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
              </div>
            </div>
            <div class="ml-5 w-0 flex-1">
              <dl>
                <dt class="text-sm font-medium text-gray-500 truncate">Pending</dt>
                <dd class="text-lg font-medium text-gray-900"><%= @pending_count %></dd>
              </dl>
            </div>
          </div>
        </div>
      </div>

      <div class="bg-white overflow-hidden shadow rounded-lg">
        <div class="p-5">
          <div class="flex items-center">
            <div class="flex-shrink-0">
              <div class="w-8 h-8 bg-blue-100 rounded-full flex items-center justify-center">
                <svg class="w-5 h-5 text-blue-600 animate-spin" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
                </svg>
              </div>
            </div>
            <div class="ml-5 w-0 flex-1">
              <dl>
                <dt class="text-sm font-medium text-gray-500 truncate">Processing</dt>
                <dd class="text-lg font-medium text-gray-900"><%= @processing_count %></dd>
              </dl>
            </div>
          </div>
        </div>
      </div>

      <div class="bg-white overflow-hidden shadow rounded-lg">
        <div class="p-5">
          <div class="flex items-center">
            <div class="flex-shrink-0">
              <div class="w-8 h-8 bg-green-100 rounded-full flex items-center justify-center">
                <svg class="w-5 h-5 text-green-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
              </div>
            </div>
            <div class="ml-5 w-0 flex-1">
              <dl>
                <dt class="text-sm font-medium text-gray-500 truncate">Processed</dt>
                <dd class="text-lg font-medium text-gray-900"><%= @processed_count %></dd>
              </dl>
            </div>
          </div>
        </div>
      </div>

      <div class="bg-white overflow-hidden shadow rounded-lg">
        <div class="p-5">
          <div class="flex items-center">
            <div class="flex-shrink-0">
              <div class="w-8 h-8 bg-gray-100 rounded-full flex items-center justify-center">
                <svg class="w-5 h-5 text-gray-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
                </svg>
              </div>
            </div>
            <div class="ml-5 w-0 flex-1">
              <dl>
                <dt class="text-sm font-medium text-gray-500 truncate">Total</dt>
                <dd class="text-lg font-medium text-gray-900"><%= @elements.count %></dd>
              </dl>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>

  <!-- Elements List -->
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 pb-8">
    <% if @elements.any? %>
      <div id="elements_list" class="space-y-4">
        <% @elements.each do |element| %>
          <%= render "element_card", element: element %>
        <% end %>
      </div>
    <% else %>
      <%= render "empty_state" %>
    <% end %>
  </div>
</div>

<%= turbo_frame_tag "modal" %>

<!-- Subscribe to real-time updates -->
<%= turbo_stream_from "project_#{@project.id}" %>
```

### 2. Element Card Partial
```erb
<!-- app/views/projects/elements/_element_card.html.erb -->
<div id="element_<%= element.id %>" class="bg-white shadow rounded-lg hover:shadow-md transition-shadow duration-200">
  <div class="p-6">
    <div class="flex items-center justify-between">
      <div class="flex-1 min-w-0">
        <div class="flex items-center space-x-3">
          <h3 class="text-lg font-medium text-gray-900 truncate">
            <%= link_to element.name, [element.project, element], 
                class: "hover:text-blue-600" %>
          </h3>
          <%= render "status_badge", element: element %>
        </div>
        
        <p class="mt-2 text-sm text-gray-600 line-clamp-2">
          <%= element.specification_preview(150) %>
        </p>
        
        <div class="mt-3 flex items-center space-x-4 text-sm text-gray-500">
          <span>
            <svg class="inline w-4 h-4 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a2 2 0 012-2z" />
            </svg>
            <%= element.element_type&.humanize || "Unclassified" %>
          </span>
          
          <% if element.confidence_score.present? %>
            <span>
              <svg class="inline w-4 h-4 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
              </svg>
              <%= number_to_percentage(element.confidence_score * 100, precision: 0) %> confidence
            </span>
          <% end %>
          
          <span>
            <svg class="inline w-4 h-4 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            <%= time_ago_in_words(element.created_at) %> ago
          </span>
        </div>
      </div>
      
      <div class="flex items-center space-x-2">
        <% if element.status == 'pending' || element.status == 'failed' %>
          <%= link_to process_project_element_path(element.project, element),
              method: :patch,
              class: "btn btn-sm btn-secondary",
              data: { turbo_method: :patch },
              title: "Process with AI" do %>
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
            </svg>
          <% end %>
        <% elsif element.status == 'processed' && element.needs_verification? %>
          <%= link_to verify_project_element_path(element.project, element),
              method: :patch,
              class: "btn btn-sm btn-success",
              data: { turbo_method: :patch },
              title: "Verify results" do %>
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
          <% end %>
        <% end %>
        
        <%= link_to edit_project_element_path(element.project, element),
            class: "btn btn-sm btn-secondary",
            data: { turbo_frame: "modal" },
            title: "Edit element" do %>
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
          </svg>
        <% end %>
      </div>
    </div>
  </div>
</div>
```

### 3. Status Badge Partial
```erb
<!-- app/views/projects/elements/_status_badge.html.erb -->
<% case element.status %>
<% when 'pending' %>
  <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-yellow-100 text-yellow-800">
    <svg class="w-3 h-3 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
    </svg>
    Pending
  </span>
<% when 'processing' %>
  <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
    <svg class="w-3 h-3 mr-1 animate-spin" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
    </svg>
    Processing
  </span>
<% when 'processed' %>
  <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
    <svg class="w-3 h-3 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
    </svg>
    Processed
  </span>
<% when 'verified' %>
  <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
    <svg class="w-3 h-3 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.586-2a1 1 0 011.414 0l2 2a1 1 0 010 1.414l-2 2a1 1 0 01-1.414 0L13 14.414" />
    </svg>
    Verified
  </span>
<% when 'failed' %>
  <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-800">
    <svg class="w-3 h-3 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16c-.77.833.192 2.5 1.732 2.5z" />
    </svg>
    Failed
  </span>
<% end %>
```

### 4. Element Show View
```erb
<!-- app/views/projects/elements/show.html.erb -->
<% content_for :title, @element.name %>

<div class="min-h-screen bg-gray-50">
  <!-- Header -->
  <div class="bg-white shadow">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
      <div class="flex items-center justify-between py-6">
        <div class="flex items-center space-x-4">
          <%= link_to project_elements_path(@project), class: "text-gray-400 hover:text-gray-600" do %>
            <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
            </svg>
          <% end %>
          <div>
            <h1 class="text-2xl font-bold text-gray-900"><%= @element.name %></h1>
            <p class="text-sm text-gray-500">
              <%= link_to @project.title, @project, class: "hover:text-gray-700" %> • 
              <%= @element.element_type&.humanize || "Unclassified" %>
            </p>
          </div>
        </div>
        
        <div class="flex items-center space-x-3">
          <%= render "status_badge", element: @element %>
          
          <% if @element.status == 'pending' || @element.status == 'failed' %>
            <%= link_to "Process", process_project_element_path(@project, @element),
                method: :patch,
                class: "btn btn-secondary",
                data: { turbo_method: :patch } %>
          <% elsif @element.status == 'processed' && @element.needs_verification? %>
            <%= link_to "Verify", verify_project_element_path(@project, @element),
                method: :patch,
                class: "btn btn-success",
                data: { turbo_method: :patch } %>
          <% end %>
          
          <%= link_to "Edit", edit_project_element_path(@project, @element), 
              class: "btn btn-secondary",
              data: { turbo_frame: "modal" } %>
        </div>
      </div>
    </div>
  </div>

  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
    <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
      <!-- Main Content -->
      <div class="lg:col-span-2 space-y-6">
        <!-- Specification -->
        <div class="bg-white shadow rounded-lg p-6">
          <h2 class="text-lg font-medium text-gray-900 mb-4">Specification</h2>
          <div class="prose max-w-none">
            <%= simple_format(@element.specification, class: "text-gray-700") %>
          </div>
        </div>

        <!-- AI Analysis -->
        <% if @element.processing_complete? %>
          <div class="bg-white shadow rounded-lg p-6">
            <div class="flex items-center justify-between mb-4">
              <h2 class="text-lg font-medium text-gray-900">AI Analysis</h2>
              <% if @element.confidence_score.present? %>
                <span class="text-sm text-gray-500">
                  <%= number_to_percentage(@element.confidence_score * 100, precision: 1) %> confidence
                </span>
              <% end %>
            </div>
            
            <% if @element.extracted_params.any? %>
              <div id="element_params">
                <%= render "shared/element_params", element: @element %>
              </div>
            <% else %>
              <p class="text-gray-500 italic">No parameters extracted</p>
            <% end %>
            
            <% if @element.ai_notes.present? %>
              <div class="mt-4 p-3 bg-blue-50 rounded-md">
                <p class="text-sm text-blue-800"><%= @element.ai_notes %></p>
              </div>
            <% end %>
          </div>
        <% end %>

        <!-- Quantities -->
        <% if @quantities.any? %>
          <div class="bg-white shadow rounded-lg p-6">
            <h2 class="text-lg font-medium text-gray-900 mb-4">Quantities</h2>
            <div class="space-y-4">
              <% @quantities.each do |quantity| %>
                <div class="border rounded-lg p-4">
                  <div class="flex justify-between items-start">
                    <div>
                      <h3 class="font-medium text-gray-900"><%= quantity.assembly.name %></h3>
                      <p class="text-sm text-gray-500"><%= quantity.assembly.description %></p>
                    </div>
                    <div class="text-right">
                      <div class="text-lg font-semibold text-gray-900">
                        <%= number_with_delimiter(quantity.calculated_amount) %>
                      </div>
                      <div class="text-sm text-gray-500"><%= quantity.assembly.unit %></div>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>

      <!-- Sidebar -->
      <div class="space-y-6">
        <!-- Quick Actions -->
        <div class="bg-white shadow rounded-lg p-6">
          <h3 class="text-sm font-medium text-gray-900 mb-4">Quick Actions</h3>
          <div class="space-y-3">
            <%= link_to edit_project_element_path(@project, @element),
                class: "w-full btn btn-secondary btn-sm",
                data: { turbo_frame: "modal" } do %>
              <svg class="w-4 h-4 mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
              </svg>
              Edit Element
            <% end %>
            
            <% if @missing_params.any? %>
              <button class="w-full btn btn-primary btn-sm" data-action="click->params#show">
                <svg class="w-4 h-4 mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
                </svg>
                Add Parameters
              </button>
            <% end %>
          </div>
        </div>

        <!-- Element Details -->
        <div class="bg-white shadow rounded-lg p-6">
          <h3 class="text-sm font-medium text-gray-900 mb-4">Details</h3>
          <dl class="space-y-3">
            <div>
              <dt class="text-xs font-medium text-gray-500 uppercase tracking-wide">Status</dt>
              <dd class="mt-1"><%= render "status_badge", element: @element %></dd>
            </div>
            
            <% if @element.element_type.present? %>
              <div>
                <dt class="text-xs font-medium text-gray-500 uppercase tracking-wide">Type</dt>
                <dd class="mt-1 text-sm text-gray-900"><%= @element.element_type.humanize %></dd>
              </div>
            <% end %>
            
            <div>
              <dt class="text-xs font-medium text-gray-500 uppercase tracking-wide">Created</dt>
              <dd class="mt-1 text-sm text-gray-900">
                <%= @element.created_at.strftime("%B %d, %Y at %I:%M %p") %>
              </dd>
            </div>
            
            <% if @element.processed_at.present? %>
              <div>
                <dt class="text-xs font-medium text-gray-500 uppercase tracking-wide">Last Processed</dt>
                <dd class="mt-1 text-sm text-gray-900">
                  <%= @element.processed_at.strftime("%B %d, %Y at %I:%M %p") %>
                </dd>
              </div>
            <% end %>
          </dl>
        </div>
      </div>
    </div>
  </div>
</div>

<%= turbo_frame_tag "modal" %>

<!-- Subscribe to real-time updates -->
<%= turbo_stream_from "project_#{@project.id}" %>
```

### 5. Element Form Partial
```erb
<!-- app/views/projects/elements/_form.html.erb -->
<%= turbo_frame_tag "modal" do %>
  <div class="fixed inset-0 z-50 overflow-y-auto" data-turbo-temporary>
    <div class="flex min-h-screen items-center justify-center p-4">
      <div class="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity" 
           data-action="click->modal#close"></div>
      
      <div class="relative w-full max-w-2xl bg-white rounded-lg shadow-xl">
        <div class="flex items-center justify-between p-6 border-b">
          <h3 class="text-lg font-medium text-gray-900">
            <%= element.persisted? ? "Edit Element" : "New Element" %>
          </h3>
          <%= link_to project_elements_path(project), 
              class: "text-gray-400 hover:text-gray-500",
              data: { turbo_frame: "_top" } do %>
            <svg class="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          <% end %>
        </div>

        <%= form_with model: [project, element], 
            data: { turbo_frame: "modal" },
            class: "p-6 space-y-6" do |form| %>
          
          <div>
            <%= form.label :name, class: "block text-sm font-medium text-gray-700" %>
            <%= form.text_field :name, 
                class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500",
                placeholder: "e.g., External Wall - North Elevation" %>
            <% if element.errors[:name].any? %>
              <p class="mt-1 text-sm text-red-600"><%= element.errors[:name].first %></p>
            <% end %>
          </div>

          <div>
            <%= form.label :specification, class: "block text-sm font-medium text-gray-700" %>
            <%= form.text_area :specification, 
                rows: 8,
                class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500",
                placeholder: "Enter the detailed specification for this element..." %>
            <% if element.errors[:specification].any? %>
              <p class="mt-1 text-sm text-red-600"><%= element.errors[:specification].first %></p>
            <% end %>
            <p class="mt-1 text-xs text-gray-500">
              Provide as much detail as possible. AI will extract dimensions, materials, and construction details.
            </p>
          </div>

          <div>
            <%= form.label :element_type, class: "block text-sm font-medium text-gray-700" %>
            <%= form.select :element_type, 
                options_for_select([
                  ["Select type...", ""],
                  ["Wall", "wall"],
                  ["Door", "door"],
                  ["Window", "window"],
                  ["Floor", "floor"],
                  ["Ceiling", "ceiling"],
                  ["Roof", "roof"],
                  ["Foundation", "foundation"],
                  ["Beam", "beam"],
                  ["Column", "column"],
                  ["Slab", "slab"],
                  ["Stairs", "stairs"],
                  ["Railing", "railing"],
                  ["Fixture", "fixture"],
                  ["Electrical", "electrical"],
                  ["Plumbing", "plumbing"],
                  ["HVAC", "hvac"]
                ], element.element_type),
                {},
                class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500" %>
          </div>

          <div class="flex justify-end space-x-3 pt-4 border-t">
            <%= link_to "Cancel", project_elements_path(project), 
                class: "btn btn-secondary",
                data: { turbo_frame: "_top" } %>
            <%= form.submit element.persisted? ? "Update Element" : "Create Element", 
                class: "btn btn-primary" %>
          </div>
        <% end %>
      </div>
    </div>
  </div>
<% end %>
```

### 6. Empty State Partial
```erb
<!-- app/views/projects/elements/_empty_state.html.erb -->
<div class="text-center py-12">
  <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
  </svg>
  <h3 class="mt-2 text-sm font-medium text-gray-900">No elements</h3>
  <p class="mt-1 text-sm text-gray-500">
    Get started by adding your first building element specification.
  </p>
  <div class="mt-6">
    <%= link_to "Add Element", new_project_element_path(@project), 
        class: "btn btn-primary",
        data: { turbo_frame: "modal" } %>
  </div>
</div>
```

## Technical Notes
- Uses Turbo Streams for real-time status updates during processing
- Modal forms for element creation/editing to maintain context
- Responsive grid layouts for mobile and desktop
- Status badges with appropriate colors and icons
- Progressive disclosure of functionality based on element state
- Live updates via Turbo Stream subscriptions

## Definition of Done
- [ ] All views render correctly with sample data
- [ ] Forms handle validation errors properly
- [ ] Real-time updates work during AI processing
- [ ] Responsive design functions on mobile/desktop
- [ ] Modal interactions work smoothly
- [ ] Status indicators update correctly
- [ ] Bulk operations interface functions properly
- [ ] Code review completed