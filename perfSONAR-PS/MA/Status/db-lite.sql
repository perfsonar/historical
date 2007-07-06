create table link_status (
  link_id varchar(255) not null,
  link_knowledge varchar(32) not null,
  start_time float not null,
  end_time float not null,
  oper_status varchar(32) not null,
  admin_status varchar(32) not null
);
