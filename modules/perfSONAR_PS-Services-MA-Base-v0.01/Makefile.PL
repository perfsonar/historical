use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME' => 'perfSONAR_PS::Services::MA_Base',
    'VERSION_FROM' => 'lib/perfSONAR_PS/Services/MA/General.pm',
    'AUTHOR' => 'Aaron Brown <aaron@internet2.edu>',
    'PREREQ_PM' => {
        "strict" => 0,
        "warnings" => 0,
        "Exporter" => 0,
        "version" => 0.50,
	"perfSONAR_PS::Common" => "v0.01",
	"perfSONAR_PS::Messages" => "v0.01",
	"Log::Log4perl" => 1.00,
    }
);
