require 'aws-sdk-s3'
require 'aws-sdk-sesv2'
require 'temporalio/activity'

require_relative 'transcript_pb'
require_relative 'summary_pb'
require_relative 'action_items_pb'
require_relative 'dtos_pb'

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

  # input is a protobuf arp.v1.EmailInput (proto/dtos.proto); the Ruby SDK's
  # default converter decodes the Temporal payload into it.
  def send_email(input)
    bucket = input.bucket
    summary = read_summary(bucket, input.summary_key)
    action_items = read_action_items(bucket, input.action_items_key)
    transcript = read_transcript_text(bucket, input.transcript_key)
    recipient = input.recipient_email

    resp = @ses.send_email(
      from_email_address: @sender,
      destination: { to_addresses: [recipient] },
      content: {
        simple: {
          subject: { data: 'Your meeting summary and action items' },
          body: { text: { data: build_body(summary, action_items, transcript) } }
        }
      }
    )
    Arp::V1::EmailResult.new(message_id: resp.message_id)
  end

  private

  # All three artifacts are proto-JSON (proto/*.proto); parse each into its
  # generated Ruby type. ignore_unknown_fields keeps us forward-compatible.
  def read_summary(bucket, key)
    json = @s3.get_object(bucket: bucket, key: key).body.read
    Arp::V1::Summary.decode_json(json, ignore_unknown_fields: true).summary
  end

  def read_action_items(bucket, key)
    json = @s3.get_object(bucket: bucket, key: key).body.read
    Arp::V1::ActionItems.decode_json(json, ignore_unknown_fields: true).action_items.to_a
  end

  # The transcript is proto-JSON (proto/transcript.proto); parse it into the
  # generated Ruby type and return the full text. ignore_unknown_fields keeps us
  # forward-compatible if new fields are added upstream.
  def read_transcript_text(bucket, key)
    json = @s3.get_object(bucket: bucket, key: key).body.read
    Arp::V1::Transcript.decode_json(json, ignore_unknown_fields: true).text
  end

  def build_body(summary, action_items, transcript)
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
    lines << ''
    lines << 'TRANSCRIPT'
    lines << '=========='
    lines << transcript
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
