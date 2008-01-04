use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME' => 'perfSONAR_PS::Topology::Common',
    'VERSION_FROM' => 'lib/perfSONAR_PS/Topology/Common.pm',
    'AUTHOR' => 'Aaron Brown <aaron@internet2.edu>',
    'PREREQ_PM' => {
	"strict" => 0,
        "warnings" => 0,
	"version" => 0.50,
	"Exporter" => 0,
	"perfSONAR_PS::Common" => "v0.01",
	"Log::Log4perl" => 1.00,
	"Test::More" => 0,
    }
);
