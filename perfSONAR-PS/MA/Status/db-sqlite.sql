create table link_status (
  link_id varchar(255) not null,
  link_knowledge varchar(32) not null,
  start_time integer not null,
  end_time integer not null,
  oper_status varchar(32) not null,
  admin_status varchar(32) not null,
 unique (link_id, start_time, end_time));
