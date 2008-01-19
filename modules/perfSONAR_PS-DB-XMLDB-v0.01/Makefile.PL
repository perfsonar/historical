use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME' => 'perfSONAR_PS::DB::XMLDB',
    'VERSION_FROM' => 'lib/perfSONAR_PS/DB/XMLDB.pm',
    'AUTHOR' => 'Aaron Brown <aaron@internet2.edu>',
    'PREREQ_PM' => {
        "strict" => 0,
        "warnings" => 0,
	"perfSONAR_PS::Common" => 0.03,
	"Log::Log4perl" => 1.00,
	"Sleepycat::DbXml" => 2.00,
    }
);
