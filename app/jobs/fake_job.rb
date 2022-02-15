class FakeJob < ApplicationJob
  queue_as :default

  def perform(*args)
    puts "I'm starting the fake job"
    # sleep 1 = sleep up to 1 second
    sleep args[0].to_i
    puts "OK I'm done now"
  end
end
