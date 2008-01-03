use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME' => 'perfSONAR_PS::DB::XMLDB',
    'VERSION_FROM' => 'lib/perfSONAR_PS/DB/XMLDB.pm',
    'AUTHOR' => 'Aaron Brown <aaron@internet2.edu>',
    'PREREQ_PM' => {
        "strict" => 0,
        "warnings" => 0,
        "version" => 0.50,
	"perfSONAR_PS::Common" => "v0.01",
	"Sleepycat::DbXml" => 2.00,
    }
);
