require 'json'
require 'aws-sdk-s3'
require 'aws-sdk-sesv2'
require 'temporalio/activity'

# Composes and sends the summary email via SES. Singleton so the SES/S3 clients
# and sender config are created once and reused across activity executions.
class Emailer
  def self.instance
    @instance ||= new
  end

  def initialize
    region = ENV['AWS_REGION'] || ENV['AWS_DEFAULT_REGION']
    @s3 = Aws::S3::Client.new(region: region)
    @ses = Aws::SESV2::Client.new(region: region)
    @sender = ENV['SES_SENDER']
    raise 'set SES_SENDER (a verified SES identity)' if @sender.nil? || @sender.empty?
  end

  # input is a Hash with string keys matching EmailInput in
  # services/workflow-ts/src/shared.ts.
  def send_email(input)
    bucket = input['bucket']
    summary = read_json(bucket, input['summaryKey'])['summary'].to_s
    action_items = read_json(bucket, input['actionItemsKey'])['actionItems'] || []
    recipient = input['recipientEmail']

    resp = @ses.send_email(
      from_email_address: @sender,
      destination: { to_addresses: [recipient] },
      content: {
        simple: {
          subject: { data: 'Your meeting summary and action items' },
          body: { text: { data: build_body(summary, action_items) } }
        }
      }
    )
    { 'messageId' => resp.message_id }
  end

  private

  def read_json(bucket, key)
    obj = @s3.get_object(bucket: bucket, key: key)
    JSON.parse(obj.body.read)
  end

  def build_body(summary, action_items)
    lines = []
    lines << 'SUMMARY'
    lines << '======='
    lines << summary
    lines << ''
    lines << 'ACTION ITEMS'
    lines << '============'
    if action_items.empty?
      lines << '(none)'
    else
      action_items.each_with_index do |item, i|
        lines << "#{i + 1}. #{item}"
      end
    end
    lines.join("\n")
  end
end

# Temporal activity registered as "sendEmail" to match the TS workflow's
# activity type (the Ruby SDK would otherwise default to the class name
# "SendEmail").
class SendEmail < Temporalio::Activity::Definition
  activity_name 'sendEmail'

  def execute(input)
    Emailer.instance.send_email(input)
  end
end
