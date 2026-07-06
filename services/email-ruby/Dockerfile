FROM ruby:3.3-slim
WORKDIR /app
# build-essential is a fallback for any native gem; temporalio ships a
# precompiled x86_64-linux gem so this is usually unused at build time.
RUN apt-get update && apt-get install -y --no-install-recommends build-essential \
    && rm -rf /var/lib/apt/lists/*
COPY Gemfile .
RUN bundle install
COPY worker.rb send_email_activity.rb transcript_pb.rb summary_pb.rb action_items_pb.rb ./
CMD ["ruby", "worker.rb"]
