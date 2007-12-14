use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME' => 'perfSONAR_PS::Services::MA::Topology',
    'VERSION_FROM' => 'lib/perfSONAR_PS/Services/MA/Topology.pm',
    'AUTHOR' => 'Aaron Brown <aaron@internet2.edu>',
    'PREREQ_PM' => {
        "strict" => 0,
        "warnings" => 0,
	"Log::Log4perl" => 1.00,
	"perfSONAR_PS::Common" => 0.01,
	"perfSONAR_PS::Messages" => 0.01,
	"perfSONAR_PS::Services::Base" => 0.01,
	"perfSONAR_PS::Topology::Common" => 0.01,
	"perfSONAR_PS::Client::Topology::XMLDB" => 0.01,
	"perfSONAR_PS::Client::LS::Remote" => 0.01,
    }
);
