#!/usr/bin/perl -w

use strict;
use warnings;

use Getopt::Long;
use File::Find;

use vars qw($VERSION);
$VERSION = 0.1;

sub help {
    my $message = shift;

    print STDERR "Error: $message\n" if ($message);

    print STDERR "Usage: courgette.pl [--features=/some/dir] [--steps=/some/dir/] [--feature_file=/some/file.feature] [--tag=some_tag] [--help]\n"
        . "  --features - Directory containing .feature test files. Default './features'\n"
        . "  --steps - Directory containing .step files. Default './features/steps'\n"
        . "  --feature_file - Individual feature file to run (instead of a directory)\n"
        . "  --tag - Run only tests marked with a given tag\n"
        . "  --help - This.\n"
    ;
    exit(1);
}

my $featureDir = './features/';
my $stepDir = $featureDir . 'steps/';
my $featureFile;
my $tag;
my $help;

GetOptions(
    'features=s'     => \$featureDir,
    'steps=s'        => \$stepDir,
    'feature_file=s' => \$featureFile,
    'tag=s'          => \$tag,
    'help'           => \$help
);

help if ($help);

if ($featureFile) {
    help("No such feature file '$featureFile'") if (!-e $featureFile);
}
else {
    help("No such directory feature directory '$featureDir'")
        if (!-d $featureDir)
    ;
}

help("No such step directory '$stepDir'") if (!-d $stepDir);

print "Running with:\n";
if ($featureFile) {
    print "  Feature File: $featureFile\n";
}
else {
    print "  Feature Directory: $featureDir\n";
}
print "  Steps: $stepDir\n";
if ($tag) {
    print "  Tagged with: $tag\n";
}

# Hash populated in __DATA__
our %StepCollection;

# Hash for helpful stuff in stepfile.
our %T;

{
    local $/ = undef;
    eval <DATA>;
    close(DATA);

    die "Horrible internal error in step test code: $@" if ($@);
}

find(
    {
        'wanted' => sub {
            my $stepFile = $File::Find::fullname;

            return unless ($stepFile =~ /_steps\.pl$/);

            local $/ = undef;
            open(STEP, $stepFile)
                or die "Cannot open step file '$stepFile': $!\n"
            ;
            eval "no strict;\n#line 1\n" . <STEP> ;
            close(STEP);
            die("Error in step file '$stepFile': $@\n") if ($@);
        },
        'follow' => 1,
    },
    $stepDir
);

my $currentScenario;
my $currentSteptype;

my @featureFiles;

if ($featureFile) {
    push @featureFiles, $featureFile;
}
else {
    find(
        {
            'wanted' => sub {
                my $thisFf = $File::Find::fullname;

                return unless ($thisFf =~ /\.feature$/);
                push @featureFiles, $thisFf;
            },
            'follow' => 1,
        },
        $featureDir
    );
}

help("No features found!") unless (@featureFiles);

foreach my $currentFeatureFile (@featureFiles) {
    open(FEATURE, $currentFeatureFile) or
        die "Cannot open feature file $currentFeatureFile: $!\n"
    ;

    my $currentStepType;

    my @table;
    my $tableLine;

    my @featureLines;
    my @tableHeader;
    my $scenarioTag;

    # preprocess tables and clean up the lines.
    while (<FEATURE>) {
        my $line = $_;
        chomp($line);
        $line =~ s/^\s+//g;
        $line =~ s/\s+$//g;

        if (!$line) {
            $scenarioTag = undef;
            next;
        }

        if ($line =~ /@.+/) {
            $scenarioTag = $line;
            $scenarioTag =~ s/^@//;
            next;
        }

        if ($line =~ /^\|/) {
            my @untidyColumns = split(/\|/, $line);
            shift(@untidyColumns);

            my @columns;

            foreach (@untidyColumns) {
                s/^\s+//;
                s/\s+$//;
                push @columns, $_;
            }

            my $tableArray = $featureLines[scalar(@featureLines) - 1]->{-tableArray} || [];
            my $tableHash = $featureLines[scalar(@featureLines) - 1]->{-tableHash} || [];            

            if (!@tableHeader) {
                @tableHeader = @columns;
            }
            else {
                push(
                    @$tableArray,
                    \@columns
                );

                my %rowHash;
                my $columnCount = 0;
                foreach (@columns) {
                    $rowHash{$tableHeader[$columnCount]} = $_;
                    $columnCount++;
                }

                push(
                    @$tableHash,
                    \%rowHash
                );
            }
        }
        else {
            @tableHeader = ();

            push @featureLines, {
                -tableArray => [],
                -tableHash => [],
                -line  => $line,
                -lineNumber => $.,
                -tag => $scenarioTag
            };
        }
    }

    # actually parse and execute features. lovely.
    foreach my $featureLine (@featureLines) {
        my $line = $featureLine->{-line};
        my $lineNumber = $featureLine->{-lineNumber};
        my $currentTag = $featureLine->{-tag};

        # if we've specified a tag, ignore all tests except those with a
        # matching tag
        next if ($tag && (!$currentTag || $currentTag ne $tag));

        if ($line =~ /^\s*Scenario:\s*(.+)/) {
            $currentScenario = $1;
            next;
        }

        if ($line =~ /^\s*(\w+)\s+(.+)/) {
            die "Error: $line ($lineNumber). Must be within a scenario."
                unless ($currentScenario)
            ;
            my ($stepType, $test) = ($1, $2);
            
            my $code;
            my @matches;

            if ($stepType eq 'And' or $stepType eq 'But') {
                $stepType = $currentStepType;
                # replace the "and" or "but" with whatever it is preceded by.
                $line =~ s/^\Q$stepType\E/\Q$currentStepType\E/;
            }
            else {
                $currentStepType = $stepType;
            }

            while (my ($regexp, $block) = each(
                %{$StepCollection{$stepType}}
            )) {
                if ($test =~ $regexp) {
                    for (1..100) {
                        my $var = '$' . $_;
                        my $val = eval $var;
                        push @matches, $val;
                    }
                    $code = $block;
                }
            }

            die
                "Error: line $lineNumber. No matching step for "
                . "'$line' in scenario '$currentScenario'.\n"
                unless ($code)
            ;

            $T{-name} = "Scenario: $currentScenario. Step: $line (line $lineNumber)";
            $T{-scenario} = $currentScenario;
            $T{-step} = $line;
            $T{-lineNumber} = $lineNumber;
            $T{-stepType} = $stepType;
            $T{-featureFile} = $currentFeatureFile;
            $T{-tableArray} = $featureLine->{-tableArray};
            $T{-tableHash} = $featureLine->{-tableHash};

            $code->(@matches);
        }
        else {
            die 
                "Error: $line ($.). "
                . "Line must be Scenario, Given, When, Then, And or But"
            ;
        }
    }

    close(FEATURE);
}

__DATA__

sub _codeCollection {
    my ($stepType, $regexp, $block) = @_;

    if ($StepCollection{$stepType}{$regexp}) {
        die "Step '$regexp' for a $stepType already exists";
    }

    $StepCollection{$stepType}{$regexp} = $block;
}

sub Given {
    _codeCollection('Given', @_);
}

sub When {
    _codeCollection('When', @_);
}

sub Then {
    _codeCollection('Then', @_);
}

__END__

=head1 NAME

courgette.pl - A Perl implementation of Aslak Hellesøy's Cucumber BDD framework.

=head1 SYNOPSIS

Assuming you have your features in './features/' and your steps in './features/steps/', you can run your Cucumber tests like this:

 courgette.pl

If your features and steps are in another directory, you can manually define them:

 courgette.pl --features=/dir/with/features --steps=/dir/with/steps

Should you wish to run a particular feature file, you can pass a single file:

 courgette.pl --feature_file=/some/file.feature

If you want to run only tagged scenarios, you can define the tag:

 courgette.pl --tag=some_tag

To run steps from a particular location and only given scenarios in a given file...

 courgette.pl --steps=/dir/with/steps --tag=some_tag --feature_file=/some/file.feature

The directories defined with '--steps' and '--features' are searched recursively for filenames that have '_steps.pl' and '.feature' on the end respectively. All other files are ignored. For example...

 using_my_website_steps.pl
 my_tests.feature

=head1 DESCRIPTION

Courgette is my Perl implementation of Cucumber. So it's like Cucumber but smaller and uglier. See the SEE ALSO section for more about Cucumber.

=head1 CUCUMBER DESCRIPTION

Having been impressed by the Cucumber Behavior Driven Development (BDD) suite for Rails, I thought it would be nice to have some basic implementation in Perl.

I won't go into much detail regarding Cucumber itself as there are websites that explain it well but the gist of it is this (see "SEE ALSO"): For BDD, you have non-developers (ideally) writing your tests. Not only does this cut down on development effort but also means no more 80 page func specs!

The structure is split down as features (the human readable test) and your steps, which will execute the actual code. Features are split into "Given", "When" and "Then". "Given" is your context (e.g. "Given I am on the home page"). "When" is the action performed (e.g. "When I click on 'blog'") and "Then" is your result check (e.g. "Then I should see 'my blogs'"). Wicked, init?

So lets see what our feature file for this will look like:

 Scenario: I want to see my blog
   Given I am on the home page
   When I click on "blogs"
   Then I will see "my blogs"

A feature file will contain many related "scenarios". The scenario is meta data and is used as an overall description of the task.

The feature file must have the extension of ".feature" and for simplicity we'll stuff it in "./features/".

So now lets have this actually do something. To do this, we need to create our step file. We'll call it "homepage_steps.pl" and it should live in "./features/steps/".

 use Test::More qw(no_plan); # we'll use this for our tests
 use HTTP::Request;

 Given qr/^I am on the home page$/, sub {
     $html = HTTP::Request->new('GET' => 'http://www.advancethinking.com');
     # see "MR T" for details on the "%T" hash.
     ok($html, $T{-name});
 };

 # any matches are passed in as parameters to the callback given below.
 When qr/^I click on "(.+)"$/, sub {
     my $urlLabel = shift;
     # $urlLabel #=> blogs
     my $content = $html->content(); # $html remains persistant

     # yeah yeah, hacky
     $content =~ /href="(.+)">$urlLabel</;

     $html = HTTP::Request->new('GET' => $1);

     ok($html, $T{-name});
 };

 Then qr/^I will see "(.+)"$/, sub {
     my $pageTitle = shift;

     like(
         $html->content,
         qr/title>$pageTitle</
     );
 };

Easy, init? Note: I've not actually tested the above! Have a look in 't/features/' of the distro to see simple examples.

What if you want to do multiple "Givens", "Whens" or "Thens"?? Well, that's easy, use an "And" or "But". For example

 Scenario: When I was born
   Given my mother is pregnant
   And she is going in to labor
   When she visits hospital
   And so does my father
   Then I will be born
   And I will be a man
   But I will not be a woman

"But" and "And" will repeat the previous step type. They are also technically identical but look pretty.

=head1 MR T

%T is an ambiguously but short named hash table that is global and available within your steps. It contains information about the current feature and step that is being run. It has the following keys...

 -name => this is a string for convenience in your tests. It contains the current scenario and step (given, when, then string).
 -step => the string of the step (e.g. "Given I am on the home page").
 -stepType => the "type" of step ("Given", "Then" or "When").
 -lineNumber => the line number being executed in the .feature file.
 -featureFile => the filename of the currently executing feature.
 -tableArray => a two dimentional array of a table (if there is one defined).
 -tableHash => actually an array of hashes. each array element represents a row and each hash key contains the column header and the value is the content of the column.

=head1 SEE ALSO

Just to scratch the surface, look in the 't/features' directory for some simple examples. Also look at the following webpages (mostly Ruby & Java):

  Cucumber home page: http://cukes.info/
  BDD & Dan North: http://dannorth.net/introducing-bdd
  Wikipedia Page: http://en.wikipedia.org/wiki/Behavior_Driven_Development
  Test::More (not mandatory but certainly useful): http://search.cpan.org/~mschwern/Test-Simple-0.86/lib/Test/More.pm

=head1 TODO

 - Add support for "Feature:" and other such Cucumberisms.
 - Case insensitivity.
 - Better, more modular code and make into distributable module.
 - Grab the usefully named "Test::Cucumber" and maybe do something useful with it.

=head1 THANKS

To Dan North for BDD and Aslak Hellesøy for Cucumber.

I better get out of bed an enjoy my birthday now!

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2009 Stephen Hardisty <moowahaha@hotmail.com>

This software is Free software and may be used and redistributed under the same terms as Perl itself.

=cut
