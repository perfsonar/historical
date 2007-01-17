drop table data;

create table data (
  id                    varchar(255) not null,
  time                  number not null,
  value                 number,
  eventtype             varchar(128) not null,
  misc                  varchar(128),
  unique (id, time, value, eventtype, misc)
)
/
