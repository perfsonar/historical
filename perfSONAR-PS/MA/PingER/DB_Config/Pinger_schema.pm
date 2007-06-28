package perfSONAR_PS::MA::PingER::DB_Config::Pinger_schema;

use base qw/DBIx::Class::Schema/;

__PACKAGE__->load_classes(qw/Pinger_pairs MetaData);


package perfSONAR_PS::MA::PingER::DB_Config::Pinger_pairs;

use DBIx::Class;
 

use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/Core/);
__PACKAGE__->table('pinger_pairs');
__PACKAGE__->add_columns(
           metaID    =>   {data_type => 'varchar', size => '52', is_nullable => 0}, 
	   pkgs_rcvd  => {data_type => 'integer', size => '4', is_unsigned => 1 },
	   ttl  => {data_type => 'integer', size => '4', is_unsigned => 1 },
	   numBytes  => {data_type => 'integer', size => '4', is_unsigned => 1 },
	   min_time   => {data_type => 'float' },
	   avrg_time  => {data_type => 'float' },
	   max_time   => {data_type => 'float' }, 
	   timestamp  => {data_type => 'integer', size => '12',   is_nullable => 0 },
	   min_delay  => {data_type => 'float'},
	   ipdv  => {data_type => 'float'},
	   max_delay => {data_type => 'float'  }, 
	   dupl => {data_type => 'tinyint', size => '1' },
	   outOfOrder => {data_type => 'tinyint', size => '1' },
	   median_time   => {data_type => 'float' },
	   clp  => {data_type => 'float' },
	   iqr_delay   => {data_type => 'float' }, 
	   lossPercent => {data_type => 'float' }, 
	  );
__PACKAGE__->set_primary_key(qw/metaID timestamp/);

package perfSONAR_PS::MA::PingER::DB_Config::MetaTable;

use DBIx::Class;
 

use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/Core/);
__PACKAGE__->table('metaData');
__PACKAGE__->add_columns( 
           metaID    =>   {data_type => 'varchar', size => '52', is_nullable => 0}, 
          ip_name_src => {data_type => 'varchar', size => '52',  }, 
          ip_name_dst => {data_type => 'varchar', size => '52' }, 
	  ip_number_src  => {data_type => 'varchar', size => '15', is_nullable => 0 },
	   ip_number_dst  => {data_type => 'varchar', size => '15', is_nullable => 0 },
	   pkg_size  => {data_type => 'integer', size => '4', is_unsigned => 1, is_nullable => 0 },
	   pkg_sent  => {data_type => 'integer', size => '4', is_unsigned => 1, is_nullable => 0 },
	   protocol  =>   {data_type => 'varchar', size => '4', is_nullable => 0}, 
	   ttl  => {data_type => 'integer', size => '4', is_unsigned => 1 }, 
	    );
__PACKAGE__->set_primary_key(qw/metaID/);
   
1;
