use 5.008009;
use ExtUtils::MakeMaker;

WriteMakefile(
    FULLPERL          => '/usr/bin/perl',
    NAME              => 'courgette',
    VERSION_FROM      => 'courgette.pl',
    EXE_FILES         => ['courgette.pl'],
    PREREQ_PM         => {
        'File::Find' => 1.13,
        'Getopt::Long' => 2.37,
        'Test::More' => 0.86,
    },
    ($] >= 5.005 ?
      (ABSTRACT_FROM  => 'courgette.pl',
       AUTHOR         => 'Stephen Hardisty <moowahaha@hotmail.com>') : ()),
);
