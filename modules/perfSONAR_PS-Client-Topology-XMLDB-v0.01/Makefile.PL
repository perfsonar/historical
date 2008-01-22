use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME' => 'perfSONAR_PS::Client::Topology::XMLDB',
    'VERSION_FROM' => 'lib/perfSONAR_PS/Client/Topology/XMLDB.pm',
    'AUTHOR' => 'Aaron Brown <aaron@internet2.edu>',
    'PREREQ_PM' => {
        "strict" => 0,
	"Log::Log4perl" => 1.00,
	"perfSONAR_PS::Common" => 0.06,
	"perfSONAR_PS::Topology::Common" => 0.06,
	"perfSONAR_PS::Topology::ID" => 0.06,
	"perfSONAR_PS::DB::XMLDB" => 0.06,
    }
);
