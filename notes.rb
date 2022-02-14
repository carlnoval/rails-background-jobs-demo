#1 add admins to protect the jobs dashboard
rails g migration AddAdminToUsers

def change
  add_column :users, :admin, :boolean, null: false, default: false
end

rails db:migrate