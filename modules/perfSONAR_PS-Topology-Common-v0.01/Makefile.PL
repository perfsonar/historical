use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME' => 'perfSONAR_PS::Topology::Common',
    'VERSION_FROM' => 'lib/perfSONAR_PS/Topology/Common.pm',
    'AUTHOR' => 'Aaron Brown <aaron@internet2.edu>',
    'PREREQ_PM' => {
	"strict" => 0,
        "warnings" => 0,
	"Exporter" => 0,
	"perfSONAR_PS::Common" => 0.04,
	"Log::Log4perl" => 1.00,
	"Test::More" => 0,
    }
);
