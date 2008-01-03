use ExtUtils::MakeMaker;

my @exe_files = ( "psLoadTopology" );

WriteMakefile(
    'NAME' => 'perfSONAR_PS::Services::MA::Topology',
    'VERSION_FROM' => 'lib/perfSONAR_PS/Services/MA/Topology.pm',
    'AUTHOR' => 'Aaron Brown <aaron@internet2.edu>',
    'PREREQ_PM' => {
        "strict" => 0,
        "warnings" => 0,
	"Log::Log4perl" => 1.00,
        "version" => 0.50,
	"perfSONAR_PS::Common" => "v0.01",
	"perfSONAR_PS::Messages" => "v0.01",
	"perfSONAR_PS::Services::Base" => "v0.01",
	"perfSONAR_PS::Topology::Common" => "v0.01",
	"perfSONAR_PS::Client::Topology::XMLDB" => "v0.01",
	"perfSONAR_PS::Client::LS::Remote" => "v0.01",
    },

    EXE_FILES => \@exe_files,
);
