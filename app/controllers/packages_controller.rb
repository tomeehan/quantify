class PackagesController < ApplicationController
  before_action :authenticate_user!
  before_action :require_account
  before_action :set_bill
  before_action :set_package, only: [:show, :edit, :update, :destroy]

  def index
    authorize @bill, :show?
    @packages = @bill.packages.order(created_at: :desc)
  end

  def show
    authorize @bill, :show?
  end

  def new
    authorize @bill, :update?
    @package = @bill.packages.new
  end

  def edit
    authorize @bill, :update?
    @full_screen = true
  end

  def create
    authorize @bill, :update?
    @package = @bill.packages.new(package_params)
    @package.account = current_account
    if @package.save
      redirect_to bill_packages_path(@bill), notice: "Package was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    authorize @bill, :update?
    if @package.update(package_params)
      redirect_to bill_packages_path(@bill), notice: "Package was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @bill, :update?
    @package.destroy
    redirect_to bill_packages_path(@bill), notice: "Package was successfully deleted."
  end

  private

  def set_bill
    @bill = current_account.bills.find(params[:bill_id])
  end

  def set_package
    @package = @bill.packages.find(params[:id])
  end

  def package_params
    params.require(:package).permit(:name)
  end
end
