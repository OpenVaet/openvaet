#!/usr/bin/perl
use strict;
use warnings;
use 5.26.0;
binmode STDOUT, ":utf8";
use utf8;

# Cpan dependencies.
no autovivification;
use Data::Printer;
use Data::Dumper;
use JSON;
use HTTP::Cookies;
use HTML::Tree;
use LWP::UserAgent;
use LWP::Simple;
use File::Path qw(make_path);
use HTTP::Cookies qw();
use HTTP::Request::Common qw(POST OPTIONS);
use HTTP::Headers;
use Hash::Merge;
use Scalar::Util qw(looks_like_number);
use Digest::MD5  qw(md5 md5_hex md5_base64);

# Project's libraries.
use FindBin;
use lib "$FindBin::Bin/../../lib";
use time;
use global;

my %reports = ();
reports();

sub reports {
    say "loading cache ...";
    my $tb = $dbh->selectall_hashref("SELECT id as reportId, vaersId, pregnancyConfirmation FROM report", 'reportId');
    for my $reportId (sort{$a <=> $b} keys %$tb) {
        my $vaersId                = %$tb{$reportId}->{'vaersId'};
        my $pregnancyConfirmation  = %$tb{$reportId}->{'pregnancyConfirmation'};
        if ($pregnancyConfirmation) {
            $pregnancyConfirmation = unpack("N", pack("B32", substr("0" x 32 . $pregnancyConfirmation, -32)));
            $reports{$vaersId}->{'pregnancyConfirmation'} = $pregnancyConfirmation;
        }
        $reports{$vaersId}->{'reportId'} = $reportId;
    }
}

my $sql = "
    SELECT
        vaersId,
        pregnancyConfirmation,
        pregnancyConfirmationRequired,
        pregnancyConfirmationTimestamp,
        aEDescription,
        childDied,
        childSeriousAE,
        onsetDate,
        vaccinationDate,
        patientAge,
        vaersReceptionDate
    FROM vaers_fertility_report WHERE pregnancyConfirmationRequired = 1";
say "$sql";
my $rTb                 = $dbh->selectall_hashref($sql, 'vaersId'); # ORDER BY RAND()
my $total    = keys %$rTb;
my $current  = 0;
my $restored = 0;
my $missing  = 0;
my $missingDeath   = 0;
my $missingSerious = 0;
my @deletedReports = ();
for my $vaersId (sort{$a <=> $b} keys %$rTb) {
    my $pregnancyConfirmationRequired       = %$rTb{$vaersId}->{'pregnancyConfirmationRequired'} // die;
    $pregnancyConfirmationRequired          = unpack("N", pack("B32", substr("0" x 32 . $pregnancyConfirmationRequired, -32)));
    my $pregnancyConfirmation               = %$rTb{$vaersId}->{'pregnancyConfirmation'};
    my $pregnancyConfirmationTimestamp      = %$rTb{$vaersId}->{'pregnancyConfirmationTimestamp'};
    $current++;
    if (defined $pregnancyConfirmation && !exists $reports{$vaersId}->{'pregnancyConfirmation'}) {
        $pregnancyConfirmation = unpack("N", pack("B32", substr("0" x 32 . $pregnancyConfirmation, -32)));
        $pregnancyConfirmationTimestamp = 'UNIX_TIMESTAMP()' unless defined $pregnancyConfirmationTimestamp;
        my $reportId = $reports{$vaersId}->{'reportId'};
        unless ($reportId) {
            $missing++;
            my $aEDescription   = %$rTb{$vaersId}->{'aEDescription'}  // die;
            my $childDied       = %$rTb{$vaersId}->{'childDied'}      // die;
            $childDied          = unpack("N", pack("B32", substr("0" x 32 . $childDied, -32)));
            my $childSeriousAE  = %$rTb{$vaersId}->{'childSeriousAE'} // die;
            $childSeriousAE     = unpack("N", pack("B32", substr("0" x 32 . $childSeriousAE, -32)));
            $missingDeath++    if $childDied;
            $missingSerious++  if $childSeriousAE;
            if ($childDied) {
                my $vaersReceptionDate       = %$rTb{$vaersId}->{'vaersReceptionDate'}      // die;
                my $onsetDate       = %$rTb{$vaersId}->{'onsetDate'};
                my $vaccinationDate       = %$rTb{$vaersId}->{'vaccinationDate'};
                my $patientAge       = %$rTb{$vaersId}->{'patientAge'};
                my %o = ();
                $o{'aEDescription'} = $aEDescription;
                $o{'vaersId'} = $vaersId;
                $o{'onsetDate'} = $onsetDate;
                $o{'vaccinationDate'} = $vaccinationDate;
                $o{'patientAge'} = $patientAge;
                $o{'vaersReceptionDate'} = $vaersReceptionDate;
                $o{'pregnancyConfirmationTimestamp'} = $pregnancyConfirmationTimestamp;
                push @deletedReports, \%o;
            }
            next;
        }
        $restored++;
        my $sth = $dbh->prepare("
            UPDATE report SET
                pregnancyConfirmation = $pregnancyConfirmation,
                pregnancyConfirmationTimestamp = $pregnancyConfirmationTimestamp,
                pregnancyConfirmationUserId = 1
            WHERE id = $reportId");
        $sth->execute(
        ) or die $sth->err();
    }
    say "[$current / $total] - restored [$restored] - missing [$missing] ($missingDeath | $missingSerious)";
}
open my $out, '>:utf8', 'deleted_reports.json';
say $out encode_json\@deletedReports;
close $out;