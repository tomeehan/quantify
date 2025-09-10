class ProjectsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_account
  before_action :set_project, only: [:show, :edit, :update, :destroy]

  def index
    @projects = policy_scope(current_account.projects).order(created_at: :desc)
    authorize Project
  end

  def show
    authorize @project
  end

  def new
    @project = current_account.projects.new
    authorize @project
  end

  def create
    @project = current_account.projects.new(project_params)
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
      redirect_to @project, notice: "Project was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @project
    @project.destroy
    redirect_to projects_path, notice: "Project was successfully deleted."
  end

  private

  def set_project
    @project = current_account.projects.find(params[:id])
  end

  def project_params
    params.require(:project).permit(:name, :address, :square_footage, :project_type)
  end
end
