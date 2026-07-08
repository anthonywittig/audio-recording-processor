# The generated bundle_pb.rb requires its imports by bare name
# (require 'transcript_pb'), so this directory must be on the load path.
$LOAD_PATH.unshift(__dir__)

require 'temporalio/client'
require 'temporalio/worker'
require_relative 'bundle_results_activity'

TASK_QUEUE = 'bundle'.freeze

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
  activities: [BundleResults]
)

puts "bundle worker started: address=#{address} namespace=#{namespace} queue=#{TASK_QUEUE}"
worker.run(shutdown_signals: ['SIGINT', 'SIGTERM'])
