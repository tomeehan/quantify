class BillsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_account
  before_action :set_project

  def create
    # Authorization: require ability to update project to create bills
    authorize @project, :update?

    @bill = current_account.bills.new(project: @project)
    if @bill.save
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.prepend(
            "bills",
            partial: "bills/row",
            locals: { bill: @bill }
          )
        end
        format.html { redirect_to @project, notice: "Bill created." }
      end
    else
      respond_to do |format|
        format.turbo_stream { head :unprocessable_entity }
        format.html { redirect_to @project, alert: @bill.errors.full_messages.to_sentence }
      end
    end
  end

  private

  def set_project
    @project = current_account.projects.find(params[:project_id])
  end
end

