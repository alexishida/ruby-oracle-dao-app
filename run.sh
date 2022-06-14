#!/bin/bash
export LD_LIBRARY_PATH=/opt/oracle/instantclient
export PATH=/opt/oracle/instantclient:/usr/local/bundle/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

gem install bundler
bundle install
ruby app.rb -e producao
