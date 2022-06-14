#!/bin/bash
export LD_LIBRARY_PATH=/opt/oracle/instantclient
export PATH=/opt/oracle/instantclient:/usr/local/bundle/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Rodando de hora em hora
# https://crontab-generator.org/
crontab -r
(crontab -l 2>/dev/null; echo "0 * * * * /bin/sh -c \"(export PATH=/usr/bin:/bin; /app/run.sh)\" > /app/log.txt") | crontab -

gem install bundler
bundle install
ruby app.rb -e producao

while true
do
	sleep 1
done
