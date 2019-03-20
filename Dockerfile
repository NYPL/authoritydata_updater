FROM ruby:2.6.2 as production

RUN apt-get update

RUN mkdir -p /opt/authoritydata_udpater
COPY . /opt/authoritydata_udpater
RUN cd /opt/authoritydata_udpater && bundle install --without test development

# Clean up APT when done.
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

CMD ["ruby", "/opt/authoritydata_udpater/authoritydata_updater.rb"]

FROM production AS development

run cd /opt/authoritydata_udpater && bundle --with test development

# It will be linked from localhost via docker-compose
run rm -rf /opt/authoritydata_udpater/*
