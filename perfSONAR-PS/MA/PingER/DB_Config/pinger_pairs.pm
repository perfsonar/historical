#!/usr/bin/perl

package perfSONAR_PS::MA::Pinger::DB_Config::Pinger_table;


use DBIx::Class;
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Common;

use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('pinger_pairs');
__PACKAGE__->add_columns(qw/ip_name_src ip_name_dst ip_number_src ip_number_dst pkg_size pkg_sent pkgs_rcvd min_time avrg_time max_time timestamp min_delay ipdv max_delay dupl/);
__PACKAGE__->set_primary_key(qw/ip_name_src ip_name_dst pkg_size timestamp/);
   
1;
