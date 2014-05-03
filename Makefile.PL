use strict;
use warnings;
use ExtUtils::MakeMaker;

# Normalize version strings like 6.30_02 to 6.3002,
# so that we can do numerical comparisons on it.
my $eumm_version = $ExtUtils::MakeMaker::VERSION;
$eumm_version =~ s/_//;

WriteMakefile(
	NAME                => 'GHMon',
	AUTHOR              => q{cahu <cahu@gmx.us>},
	VERSION_FROM        => 'lib/GHMon.pm',
	($eumm_version >= 6.3001
		? ('LICENSE'=> 'perl')
		: ()),
	PL_FILES            => {},
	PREREQ_PM => {
		'Test::More' => 0,
		'YAML'       => 0,
		'Template'   => 0,
		'Dancer'     => 1.3123,
		'RyzomAPI'   => 0.4,
	},
	dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
	clean               => { FILES => 'GHMon-*' },
);
