FROM ruby:2.7

WORKDIR /opt/updater

COPY Gemfile .
COPY Gemfile.lock .
RUN bundle install

COPY . .
