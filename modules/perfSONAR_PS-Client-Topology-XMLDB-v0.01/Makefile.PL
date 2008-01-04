use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME' => 'perfSONAR_PS::Client::Topology::XMLDB',
    'VERSION_FROM' => 'lib/perfSONAR_PS/Client/Topology/XMLDB.pm',
    'AUTHOR' => 'Aaron Brown <aaron@internet2.edu>',
    'PREREQ_PM' => {
        "strict" => 0,
        "version" => 0.50,
	"Log::Log4perl" => 1.00,
	"perfSONAR_PS::Common" => "v0.01",
	"perfSONAR_PS::Topology::Common" => "v0.01",
	"perfSONAR_PS::Topology::ID" => "v0.01",
	"perfSONAR_PS::DB::XMLDB" => "v0.01",
    }
);
