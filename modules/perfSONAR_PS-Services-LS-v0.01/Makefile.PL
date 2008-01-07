use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME' => 'perfSONAR_PS::Services::LS',
    'VERSION_FROM' => 'lib/perfSONAR_PS/Services/LS/LS.pm',
    'AUTHOR' => 'Aaron Brown <aaron@internet2.edu>',
    'PREREQ_PM' => {
        "strict" => 0,
        "warnings" => 0,
        "Exporter" => 0,
	"Log::Log4perl" => 1.00,
	"Time::HiRes" => 1.85,
        "version" => 0.50,
	"perfSONAR_PS::Common" => 'v0.01',
	"perfSONAR_PS::Messages" => 'v0.01',
	"perfSONAR_PS::Services::Base" => 'v0.01',
	"perfSONAR_PS::Services::MA::General" => 'v0.01',
	"perfSONAR_PS::DB::XMLDB" => 'v0.01',
    }
);
