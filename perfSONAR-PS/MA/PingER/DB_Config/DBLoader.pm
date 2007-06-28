package perfSONAR_PS::MA::PingER::DB_Config::DBLoader;


use DBIx::Class::Schema::Loader;
 

use base qw/DBIx::Class::Schema::Loader/;

__PACKAGE__->load_options(relationships => 1);
1;
