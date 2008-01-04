use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME' => 'perfSONAR_PS::DB::RRD',
    'VERSION_FROM' => 'lib/perfSONAR_PS/DB/RRD.pm',
    'AUTHOR' => 'Aaron Brown <aaron@internet2.edu>',
    'PREREQ_PM' => {
        "strict" => 0,
        "warnings" => 0,
	"Log::Log4perl" => 1.00,
        "version" => 0.50,
	"perfSONAR_PS::Common" => "v0.01",
	"RRDp" => 1.20,
	"Data::Compare" => 0,
	"Test::More" => 0,
    }
);
