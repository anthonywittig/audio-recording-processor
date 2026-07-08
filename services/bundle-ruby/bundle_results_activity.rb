require 'aws-sdk-s3'
require 'temporalio/activity'

require_relative 'transcript_pb'
require_relative 'summary_pb'
require_relative 'action_items_pb'
require_relative 'bundle_pb'
require_relative 'dtos_pb'

# Combines the three per-stage artifacts into one arp.v1.Bundle document in S3
# (bundles/<name>.bundle.json). Singleton so the S3 client is created once and
# reused across activity executions.
#
# NOT named "Bundler" — that collides with Ruby's bundler gem namespace.
class ResultsBundler
  def self.instance
    @instance ||= new
  end

  def initialize
    region = ENV['AWS_REGION'] || ENV['AWS_DEFAULT_REGION']
    @s3 = Aws::S3::Client.new(region: region)
  end

  # input is a protobuf arp.v1.BundleInput (proto/dtos.proto); the Ruby SDK's
  # default converter decodes the Temporal payload into it.
  def bundle(input)
    bucket = input.bucket
    transcript = read(bucket, input.transcript_key, Arp::V1::Transcript)
    summary = read(bucket, input.summary_key, Arp::V1::Summary)
    action_items = read(bucket, input.action_items_key, Arp::V1::ActionItems)

    bundle = Arp::V1::Bundle.new(
      audio_key: transcript.audio_key,
      transcript: transcript,
      summary: summary,
      action_items: action_items
    )

    bundle_key = derive_bundle_key(input.transcript_key)
    @s3.put_object(
      bucket: bucket,
      key: bundle_key,
      # emit_defaults => always-print fields, matching the other proto-JSON writers.
      body: Arp::V1::Bundle.encode_json(bundle, emit_defaults: true),
      content_type: 'application/json'
    )
    # Plain PUT (idempotent overwrite), so Temporal retries are safe.

    Arp::V1::BundleResult.new(bundle_key: bundle_key)
  end

  private

  # All three artifacts are proto-JSON (proto/*.proto); parse each into its
  # generated Ruby type. ignore_unknown_fields keeps us forward-compatible.
  def read(bucket, key, type)
    json = @s3.get_object(bucket: bucket, key: key).body.read
    type.decode_json(json, ignore_unknown_fields: true)
  end

  # Maps transcripts/<name>.json -> bundles/<name>.bundle.json (same derivation
  # pattern as the summarize and action-items workers).
  def derive_bundle_key(transcript_key)
    base = transcript_key.sub(%r{\Atranscripts/}, '').sub(/\.json\z/, '')
    "bundles/#{base}.bundle.json"
  end
end

# Temporal activity registered as "bundleResults" to match the TS workflow's
# activity type (the Ruby SDK would otherwise default to the class name).
class BundleResults < Temporalio::Activity::Definition
  activity_name 'bundleResults'

  def execute(input)
    ResultsBundler.instance.bundle(input)
  end
end
