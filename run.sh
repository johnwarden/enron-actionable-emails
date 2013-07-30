#!/bin/sh

#wget --no-check-certificate  https://s3.amazonaws.com/rjurney_public_web/images/enron.mysql.5.5.20.sql.gz
#gunzip https://s3.amazonaws.com/rjurney_public_web/images/enron.mysql.5.5.20.sql.gz
mysql5 -u root -p -e 'drop database enron'
mysql5 -u root -p -e 'create database enron'
mysql5 -u root -p < /tmp/enron.mysql.5.5.20.sql
mysql5 -u root -p < create-training-data.sql

java -Xms512M -Xmx1524M -jar stanford-classifier-2013-06-20/stanford-classifier.jar -prop actionable-emails.prop