use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME' => 'perfSONAR_PS::Client::Status::SQL',
    'VERSION_FROM' => 'lib/perfSONAR_PS/Client/Status/SQL.pm',
    'AUTHOR' => 'Aaron Brown <aaron@internet2.edu>',
    'PREREQ_PM' => {
        "strict" => 0,
        "version" => 0.50,
	"Log::Log4perl" => 1.00,
	"perfSONAR_PS::DB::SQL" => "v0.01",
	"perfSONAR_PS::Status::Link" => "v0.01",
	"perfSONAR_PS::Status::Common" => "v0.01",
    }
);
