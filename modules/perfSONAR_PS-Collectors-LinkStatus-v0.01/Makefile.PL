use ExtUtils::MakeMaker;

my @exe_files = ( "genLinkStatus.pl" );

WriteMakefile(
    'NAME' => 'perfSONAR_PS::Collectors::LinkStatus',
    'VERSION_FROM' => 'lib/perfSONAR_PS/Collectors/LinkStatus.pm',
    'AUTHOR' => 'Aaron Brown <aaron@internet2.edu>',
    'PREREQ_PM' => {
        "strict" => 0,
        "warnings" => 0,
	"fields" => 0,
        "version" => 0.50,
	"Exporter" => 0,
	"Log::Log4perl" => 1.00,
	"Net::SNMP" => "5.0.0",
	"Time::HiRes" => 1.85,
	"perfSONAR_PS::Common" => "v0.01",
	"perfSONAR_PS::DB::File" => "v0.01",
	"perfSONAR_PS::Status::Common" => "v0.01",
	"perfSONAR_PS::Client::Status::MA" => "v0.01",
    },

    EXE_FILES => \@exe_files,
);
