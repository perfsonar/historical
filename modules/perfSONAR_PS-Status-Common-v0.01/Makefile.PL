use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME' => 'perfSONAR_PS::Status::Common',
    'VERSION_FROM' => 'lib/perfSONAR_PS/Status/Common.pm',
    'AUTHOR' => 'Aaron Brown <aaron@internet2.edu>',
    'PREREQ_PM' => {
        "warnings" => 0,
	"Exporter" => 0,
        "version" => 0.50,
	"Log::Log4perl" => 1.00,
    }
);
