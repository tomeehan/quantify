class DashboardController < ApplicationController
  def show
    redirect_to projects_path
  end
end
