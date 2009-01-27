#!/bin/bash

MAKEROOT=""
if [[ $EUID -ne 0 ]]; then
    MAKEROOT="sudo "
fi

$MAKEROOT cpan DBI
$MAKEROOT cpan DBD::SQLite
$MAKEROOT cpan Data::Dumper
$MAKEROOT cpan Digest::MD5
$MAKEROOT cpan English
$MAKEROOT cpan Exporter
$MAKEROOT cpan IO::File
$MAKEROOT cpan LWP::Simple
$MAKEROOT cpan LWP::UserAgent
$MAKEROOT cpan Log::Log4perl
$MAKEROOT cpan Module::Load
$MAKEROOT cpan Net::Ping
$MAKEROOT cpan Net::SNMP
$MAKEROOT cpan Params::Validate
$MAKEROOT cpan Time::HiRes
$MAKEROOT cpan XML::LibXML
$MAKEROOT cpan base
$MAKEROOT cpan fields
$MAKEROOT cpan strict
$MAKEROOT cpan warnings
