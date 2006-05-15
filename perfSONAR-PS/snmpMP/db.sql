drop database netradar;

create database netradar;

use netradar;

create table data (
  id			int unsigned not null,  
  time			int unsigned not null,
  value			int unsigned,
  eventtype		varchar(128) not null,
  misc			varchar(128), 
  unique (id, time, value, eventtype, misc)
);
