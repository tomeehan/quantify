class ProjectPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.all
    end
  end

  def index?
    account_user.present?
  end

  def show?
    account_user.present?
  end

  def create?
    account_user.admin?
  end

  def update?
    account_user.admin?
  end

  def destroy?
    account_user.admin?
  end
end

