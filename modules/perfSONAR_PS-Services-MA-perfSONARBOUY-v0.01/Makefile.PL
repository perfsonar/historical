use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME' => 'perfSONAR_PS::Services::MA::perfSONARBOUY',
    'VERSION_FROM' => 'lib/perfSONAR_PS/Services/MA/perfSONARBOUY.pm',
    'AUTHOR' => 'Jason Zurawski <zurawski@internet2.edu>',
    'PREREQ_PM' => {
        "strict" => 0,
        "warnings" => 0,
	"perfSONAR_PS::Common" => 0.06,
	"perfSONAR_PS::Transport" => 0.06,
	"perfSONAR_PS::Messages" => 0.06,
	"perfSONAR_PS::DB::SQL" => 0.06,
	"perfSONAR_PS::DB::File" => 0.06,
	"perfSONAR_PS::Services::Base" => 0.06,
	"perfSONAR_PS::Services::MA::General" => 0.06,
	"perfSONAR_PS::XML::Document_string" => 0.06,
	"perfSONAR_PS::Error_compat" => 0.06,
	"Log::Log4perl" => 1.00,
	"Module::Load" => 0.10,
    }
);
