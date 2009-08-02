# hyper quickly written test but it uses test::more output for a realistic
# affect.
# TODO: more tests!

use Test::More tests => 8;

my $exe = './courgette.pl';
my $featureDir = 't/features/';
my $stepDir = $featureDir . 'steps/';

my $output = `$exe --features=$featureDir --steps=$stepDir 2>&1`;

like(
    $output,
    qr/ok \d+ - /,
    'output some passing test'
);

foreach my $expected (
    qr/\nok \d+\s+-\s+Scenario: This is my basic test. Step: Then I will have no file /,
    qr/\nok \d+\s+-\s+Scenario: This is my basic test with a given filename. Step: Then I will have no file/,
    qr/\nok \d+\s+-\s+Scenario: This is a test for tables.. Step: Then the 1st column in the 1st row will contain "some data 1.1"/,
    qr/\nok \d+\s+-\s+Scenario: This is a test for tables.. Step: And the 2nd column in the 2nd row will contain "some data 2.2"/,
    qr/\nok \d+\s+-\s+Scenario: Only this test will run when I specify "test_tag". Step: Then I will have no file/,
) {
    like(
        $output,
        $expected
    );
}

$output = `$exe --features=$featureDir --steps=$stepDir --tag=test_tag 2>&1`;

like(
    $output,
    qr/\nok \d+\s+-\s+Scenario: Only this test will run when I specify "test_tag". Step: Then I will have no file/
);

unlike(
    $output,
    qr/\nok \d+\s+-\s+Scenario: This is my basic test/
);

