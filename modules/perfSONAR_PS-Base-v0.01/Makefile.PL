use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME' => 'perfSONAR_PS::Base',
    'VERSION' => 'v0.01',
    'AUTHOR' => 'Aaron Brown <aaron@internet2.edu>',
    'PREREQ_PM' => {
        "strict" => 0,
	"warnings" => 0,
        "version" => 0.50,
	"Exporter" => 0,
	"Log::Log4perl" => 1.00,
	"Time::HiRes" => 1.85,
	"IO::File" => 0,
	"XML::LibXML" => 1.60,
	"LWP::UserAgent" => 2.032,
	"Params::Validate" => 0.70,
	"Data::Compare" => 0.09,
	"Error::Simple" => 0,
	"Test::More" => 0,
    }
);
