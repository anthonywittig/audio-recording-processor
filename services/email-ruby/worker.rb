require 'temporalio/client'
require 'temporalio/worker'
require_relative 'send_email_activity'

TASK_QUEUE = 'email'.freeze

def getenv(key, default)
  v = ENV[key]
  v.nil? || v.empty? ? default : v
end

address = getenv('TEMPORAL_ADDRESS', 'localhost:7233')
namespace = getenv('TEMPORAL_NAMESPACE', 'default')

client = Temporalio::Client.connect(address, namespace)

worker = Temporalio::Worker.new(
  client: client,
  task_queue: TASK_QUEUE,
  activities: [SendEmail]
)

puts "email worker started: address=#{address} namespace=#{namespace} queue=#{TASK_QUEUE}"
worker.run(shutdown_signals: ['SIGINT', 'SIGTERM'])
