package perfSONAR_PS::DB::DBLoader;


use DBIx::Class::Schema::Loader;
 

use base qw/DBIx::Class::Schema::Loader/;

__PACKAGE__->loader_options(relationships => 1);

1;
