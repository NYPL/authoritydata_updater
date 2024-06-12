FROM ruby:3.3.2 AS development

ENV HOME /root

COPY Gemfile /home/app/authoritydata_updater/
COPY Gemfile.lock /home/app/authoritydata_updater/
WORKDIR /home/app/authoritydata_updater
RUN bundle install
