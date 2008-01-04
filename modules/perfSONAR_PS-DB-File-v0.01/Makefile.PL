use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME' => 'perfSONAR_PS::DB::File',
    'VERSION_FROM' => 'lib/perfSONAR_PS/DB/File.pm',
    'AUTHOR' => 'Aaron Brown <aaron@internet2.edu>',
    'PREREQ_PM' => {
        "strict" => 0,
        "warnings" => 0,
	"Log::Log4perl" => 1.00,
        "version" => 0.50,
	"XML::LibXML" => 1.60,
	"Data::Compare" => 0,
	"Test::More" => 0,
    }
);
