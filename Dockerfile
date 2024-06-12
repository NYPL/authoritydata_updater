FROM ruby:2.7 AS development

ENV HOME /root

COPY Gemfile /home/app/authoritydata_updater/
COPY Gemfile.lock /home/app/authoritydata_updater/
WORKDIR /home/app/authoritydata_updater
RUN gem install bundler -v 2.4.22
RUN bundle install
