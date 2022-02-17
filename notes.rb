#1** add admins to protect the jobs dashboard
rails g migration AddAdminToUsers

def change
  add_column :users, :admin, :boolean, null: false, default: false
end

rails db:migrate

#2** generate first job, performs job right away
rails generate job fake
# or
rails g job fake

# rails creates 2 files, 1 for test and another file in:
# app/jobs
class FakeJob < ApplicationJob
  queue_as :default

  # perform method name is not optional it has to be `perform`
  # may/maynot have (*args)
  def perform(*args)
    # Do something later
  end
end

#3** Asynchronicity SETUP, performs job on a later time
# requires redis - Redis is a key-value store. Think of it as a PostgreSQL database that stores hashes in memory.
# more about redis - https://redis.io/

# On OSX
brew update
brew install redis
brew services start redis

# add new gems
gem 'sidekiq'
gem 'sidekiq-failures', '~> 1.0'

# run into terminal
bundle install
bundle binstub sidekiq  # enables sidekiq commands in terminal

# config/application.rb
class Application < Rails::Application
  # [...]
  config.active_job.queue_adapter = :sidekiq
end

# config/routes.rb
Rails.application.routes.draw do
  # Sidekiq Web UI, only for admins.
  require "sidekiq/web"
  authenticate :user, ->(user) { user.admin? } do
    mount Sidekiq::Web => '/sidekiq'
  end
end

# file needs to be created manually: `config/sidekiq.yml`
# commented out cause its a .yml
# :concurrency: 3
# :timeout: 60
# :verbose: true
# :queues:
#   # Queue priority:
#   # https://github.com/mperham/sidekiq/wiki/Advanced-Options
#   # https://mikerogers.io/2019/06/06/rails-6-sidekiq-queues
#   - default
#   - mailers
#   - active_storage_analysis
#   - active_storage_purge

# notes on above yaml config
# :concurrency: 3   is the number of workers
# :timeout: 60      max alloted time for the job to complete
# :verbose: true    for extra logs
# :queues:          order of job per periority, on top means higher priority

#4** Using Active job

# Open a new terminal tab and run:
sidekiq
# One more terminal, in `rails c` run:
FakeJob.perform_later # IMPORTANT!!!, sidekiq must be started just run `sidekiq` on a dedicated terminal, as per previous setup: `brew services start redis`
# perform_later means run the job on the background
# perform_now means run the job right after the command has been entered

# Sample Result:
# [3] pry(main)> FakeJob.perform_later 3
# Enqueued FakeJob (Job ID: 41beae2e-a580-4797-9b4a-5d10efa1f52e) to Sidekiq(default) with arguments: 3
# => #<FakeJob:0x00007fd6e10e2788
#  @arguments=[3],
#  @exception_executions={},
#  @executions=0,
#  @job_id="41beae2e-a580-4797-9b4a-5d10efa1f52e",
#  @priority=nil,
#  @provider_job_id="d570c74d5c6338a9062d2aea",
#  @queue_name="default",
#  @timezone="UTC">
# [4] pry(main)> 

10.times { FakeJob.perform_later 3 }
# result from previous goes like this:
# 3 jobs will be performed concurrently
# the job will only take around 12 seconds instead of 30 seconds

#5** emails as arguments
rails g job UpdateUser  # again, creates 2 files, 1 test, the other is:
# app/jobs/update_user_job.rb
class UpdateUserJob < ApplicationJob
  queue_as :default

  def perform(user)  # originally: def perform(*args)
    # Do something later
  end
end

# create user
User.create!(email: "carl@email.com", password: "123456", admin: true)

# use the job with the user
UpdateUserJob.perform_later User.first

# http://localhost:3000/sidekiq/ as an admin will show a sidekiq dashboard


#6** Global ID (1/2)
# When a Job is enqueued, the arguments are serialized.
# ActiveJob uses Global ID to convert user into a String:
user = User.find(1)
user.to_global_id #=> #<GlobalID:0x000055988bc4dd20 [...] gid://background-jobs-demo/User/1>>
user.to_global_id.to_s #=> "gid://background-jobs-demo/User/1"
#6** Global ID (2/2)
# Before performing the job, ActiveJob deserializes the user in the background:
user = GlobalID.find(serialized_user) #=>  #<User id: 1 [...]>
# BEWARE!!! if you use another framework for background jobs (e.g. Sidekiq::Worker), pass ids or strings as arguments, not full objects.

#7** Enqueue from a model
# NOTE: lecture did not do this
# app/models/user.rb
class User < ApplicationRecord
  # [...]

  # after_commit is a callback after creation of a model
  after_commit :async_update # Run on create & update

  private

  def async_update
    UpdateUserJob.perform_later(self)
  end
end

#8** Enqueue from a controller
# NOTE: lecture did not do this
# app/controllers/profiles_controller.rb
class ProfilesController < ApplicationController
  def update
    if current_user.update(user_params)
      UpdateUserJob.perform_later(current_user)  # <- The job is queued
      flash[:notice] = "Your profile has been updated"
      redirect_to root_path
    else
      render :edit
    end
  end

  private

  def user_params
    # Some strong params of your choice
  end
end

#9** Enqueue from a rake task (1)

# make own rake task
# task below creates the file: lib/tasks/user.rake
# namespace :user, task update_all
rails g task user update_all

# file contents: contains a task like so
namespace :user do
  desc "TODO"
  task update_all: :environment do
  end

end

# from kitt notes
namespace :user do
  desc "Enriching all users with Clearbit (async)"
  task update_all: :environment do
    users = User.all
    puts "Enqueuing update of #{users.size} users..."
    users.each do |user|
      UpdateUserJob.perform_later(user)
    end
    # rake task will return when all jobs are _enqueued_ (not done).
  end
end

# how to see the newly create task
# rails -T | grep user
# can run it with
rails user:update_all
# above comman generates:
# rails-background-jobs-demo git:(master) ✗ rails user:update_all
# Enqueuing update of 1 users...

#10** Enqueue from a rake task (2)
namespace :user do
  # ...
  desc "Enriching a given user with Clearbit (sync)"
  # how to get an argument through rake task
  task :update, [:user_id] => :environment do |t, args|
    user = User.find(args[:user_id])
    puts "Enriching #{user.email}..."
    # usually picking a specific id correlats with doing the job now than later
    UpdateUserJob.perform_now(user)
    # rake task will return when job is _done_
  end
end

# sample to run
# noglob is so that brackets don't need to be escapted[]
noglob rails user:update[1]
# w/o noglob -> rails user:update\[1\]
# output sample
# rails-background-jobs-demo git:(master) ✗ noglob rails user:update[1]
# Enriching carl@email.com...
# Calling Clearbit API for carl@email.com...
# Done! Enriched carl@email.com with Clearbit
# rails-background-jobs-demo git:(master) ✗ 

# 11** Mailers
# No need to write a job, just call deliver_later.
# try using user instead of user_id
UserMailer.welcome(user_id).deliver_later
(Enqueued to the mailers queue)

# More about Mailers in Rails: https://kitt.lewagon.com/knowledge/tutorials/mailing

#12** Delay the job
FakeJob.set(wait: 1.minute).perform_later

FakeJob.set(wait_until: Date.tomorrow.noon).perform_later
# By default, Sidekiq checks for scheduled job every 5 seconds (see doc: https://github.com/mperham/sidekiq/wiki/Scheduled-Jobs#checking-for-new-jobs).


#13 Heroku SETUP
# Have to use Redis Cloud: https://elements.heroku.com/addons/rediscloud
# 0. Make sure to have a Heroku server: heroku create rails-background-jobs-demo --region=us
# 1. Run on command line (requires cc on heroku account):
# heroku addons:create rediscloud
# 2. Create file: config/initializers/redis.rb, add below codes
$redis = Redis.new

# will never run on development, only on heroku
url = ENV["REDISCLOUD_URL"]

if url
  Sidekiq.configure_server do |config|
    config.redis = { url: url }
  end

  Sidekiq.configure_client do |config|
    config.redis = { url: url }
  end
  $redis = Redis.new(:url => url)
end
# 3. Create a Procfile file on same lvl as app or bin or config folders like yarn.lock
# paste below contents
# web: bundle exec puma -C config/puma.rb
# worker: bundle exec sidekiq -C config/sidekiq.yml
# 4. commit, push to heroku
# git add .
# git commit -m "heroku setup for sidekiq"
# git push heroku master
# don't forge to: `bundle lock --add-platform x86_64-linux` if ran into: remote:  !     Failed to install gems via Bundler.
# git add .
# git commit -m "add platform x86_64-linux"
# 5. Turn on sidekiq on heroku:
# in https://dashboard.heroku.com/apps/rails-background-jobs-demo/resources
# Under Free Dynos, find: worker bundle exec sidekiq -C config/sidekiq.yml 
# toggle the switch on
# 6. Create jobs with free Heroku Scheduler, search from Resources > Add Ons
# for eg use
rails user:update_all
# to run every 10 mins
# 7. More reading on Heroku scheduler: https://devcenter.heroku.com/articles/scheduler
# 8. Add at least 1 worker
# heroku ps:scale worker=1
# heroku ps # Check worker dyno is running
