# Ticket 3: Create Project Views

**Epic**: M1 Project Creation  
**Story Points**: 3  
**Dependencies**: 002-projects-controller.md

## Description
Create comprehensive views for the Projects CRUD interface. Views should follow Jumpstart Pro design patterns, use TailwindCSS for styling, and integrate Hotwire for enhanced user experience.

## Acceptance Criteria
- [ ] Projects index page with project listing
- [ ] Project show page with details and navigation  
- [ ] New/Edit project forms with validation display
- [ ] Responsive design for desktop and mobile
- [ ] Hotwire integration for smooth interactions
- [ ] Consistent styling with Jumpstart Pro theme

## Code to be Written

### 1. Projects Index View
```erb
<!-- app/views/projects/index.html.erb -->
<% content_for :title, "Projects" %>

<div class="flex items-center justify-between">
  <div>
    <h1 class="text-2xl font-bold text-gray-900">Projects</h1>
    <p class="mt-1 text-sm text-gray-500">
      Manage your BoQ projects and specifications
    </p>
  </div>
  
  <%= link_to "New Project", new_project_path, 
      class: "btn btn-primary", 
      data: { turbo_frame: "modal" } %>
</div>

<div class="mt-8">
  <% if @projects.any? %>
    <div class="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
      <% @projects.each do |project| %>
        <%= render "project_card", project: project %>
      <% end %>
    </div>
  <% else %>
    <%= render "empty_state" %>
  <% end %>
</div>

<%= turbo_frame_tag "modal" %>
```

### 2. Project Show View
```erb
<!-- app/views/projects/show.html.erb -->
<% content_for :title, @project.title %>

<div class="min-h-screen bg-gray-50">
  <div class="bg-white shadow">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
      <div class="flex items-center justify-between py-6">
        <div class="flex items-center space-x-4">
          <%= link_to projects_path, class: "text-gray-400 hover:text-gray-600" do %>
            <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
            </svg>
          <% end %>
          <div>
            <h1 class="text-2xl font-bold text-gray-900"><%= @project.title %></h1>
            <p class="text-sm text-gray-500"><%= @project.client %></p>
          </div>
        </div>
        
        <div class="flex items-center space-x-3">
          <%= link_to "Edit Project", edit_project_path(@project), 
              class: "btn btn-secondary",
              data: { turbo_frame: "modal" } %>
        </div>
      </div>
    </div>
  </div>

  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
    <div class="bg-white shadow rounded-lg p-6">
      <h2 class="text-lg font-medium text-gray-900 mb-4">Project Details</h2>
      
      <dl class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div>
          <dt class="text-sm font-medium text-gray-500">Client</dt>
          <dd class="mt-1 text-sm text-gray-900"><%= @project.client %></dd>
        </div>
        <div>
          <dt class="text-sm font-medium text-gray-500">Region</dt>
          <dd class="mt-1 text-sm text-gray-900"><%= @project.region %></dd>
        </div>
        <div class="sm:col-span-2">
          <dt class="text-sm font-medium text-gray-500">Address</dt>
          <dd class="mt-1 text-sm text-gray-900"><%= @project.address %></dd>
        </div>
      </dl>
    </div>
  </div>
</div>

<%= turbo_frame_tag "modal" %>
```

## Technical Notes
- Use Turbo Frame for modal interactions
- Implement responsive design with TailwindCSS
- Follow Jumpstart Pro design patterns
- Use semantic HTML for accessibility

## Definition of Done
- [ ] All views render correctly
- [ ] Forms handle validation errors properly
- [ ] Responsive design works on mobile/desktop
- [ ] Hotwire interactions function smoothly
- [ ] Code review completed