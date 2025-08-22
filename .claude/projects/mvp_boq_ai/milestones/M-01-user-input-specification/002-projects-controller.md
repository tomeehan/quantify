# Ticket 2: Create Projects Controller

**Epic**: M1 Project Creation  
**Story Points**: 3  
**Dependencies**: 001-project-model.md

## Description
Create the Projects controller that handles CRUD operations for projects. Controller should follow Jumpstart Pro patterns for account-scoped resources and include proper authorization.

## Acceptance Criteria
- [ ] Projects controller with index, show, new, create, edit, update, destroy actions
- [ ] Account-scoped queries (current_account.projects)
- [ ] Pundit authorization policy integration
- [ ] Strong parameters for project attributes
- [ ] Hotwire-compatible responses (Turbo Stream)
- [ ] Flash messages for user feedback
- [ ] Error handling and validation display

## Code to be Written

### 1. Projects Controller
```ruby
# app/controllers/projects_controller.rb
class ProjectsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_project, only: [:show, :edit, :update, :destroy]

  def index
    @projects = current_account.projects.recent.includes(:account)
    authorize @projects
  end

  def show
    authorize @project
  end

  def new
    @project = current_account.projects.build
    authorize @project
  end

  def create
    @project = current_account.projects.build(project_params)
    authorize @project

    if @project.save
      redirect_to @project, notice: "Project was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @project
  end

  def update
    authorize @project

    if @project.update(project_params)
      respond_to do |format|
        format.html { redirect_to @project, notice: "Project was successfully updated." }
        format.turbo_stream { flash.now[:notice] = "Project updated successfully." }
      end
    else
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.turbo_stream { render turbo_stream: turbo_stream.replace("project_form", partial: "form", locals: { project: @project }) }
      end
    end
  end

  def destroy
    authorize @project
    @project.destroy

    respond_to do |format|
      format.html { redirect_to projects_path, notice: "Project was successfully deleted." }
      format.turbo_stream { flash.now[:notice] = "Project deleted successfully." }
    end
  end

  private

  def set_project
    @project = current_account.projects.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to projects_path, alert: "Project not found."
  end

  def project_params
    params.require(:project).permit(:client, :title, :address, :region, :description)
  end
end
```

### 2. Pundit Policy
```ruby
# app/policies/project_policy.rb
class ProjectPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.admin?
        scope.all
      else
        scope.joins(:account).where(accounts: { id: user.account_ids })
      end
    end
  end

  def index?
    user.present?
  end

  def show?
    user_can_access_project?
  end

  def new?
    user.present?
  end

  def create?
    user.present? && user_can_access_account?
  end

  def edit?
    user_can_access_project?
  end

  def update?
    user_can_access_project?
  end

  def destroy?
    user_can_access_project? && (user.admin? || user_is_account_owner?)
  end

  private

  def user_can_access_project?
    user.present? && user.account_ids.include?(record.account_id)
  end

  def user_can_access_account?
    user.present? && user.account_ids.include?(record.account_id)
  end

  def user_is_account_owner?
    user.account_users.find_by(account: record.account)&.owner?
  end
end
```

## Technical Notes
- Use `current_account.projects` for automatic scoping
- Include Pundit authorization on all actions
- Set up proper error handling for RecordNotFound
- Use Hotwire/Turbo Stream for enhanced UX
- Follow RESTful conventions

## Definition of Done
- [ ] Controller passes all tests
- [ ] Pundit policy implemented and tested
- [ ] Routes configured correctly
- [ ] Error handling works properly
- [ ] Hotwire responses function correctly
- [ ] Code review completed