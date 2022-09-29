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
    my $tb = $dbh->selectall_hashref("SELECT id as reportId, vaersId, pregnancyConfirmation, pregnancySeriousnessConfirmation FROM report", 'reportId');
    for my $reportId (sort{$a <=> $b} keys %$tb) {
        my $vaersId                 = %$tb{$reportId}->{'vaersId'};
        my $pregnancyConfirmation   = %$tb{$reportId}->{'pregnancyConfirmation'};
        my $pregnancySeriousnessConfirmation = %$tb{$reportId}->{'pregnancySeriousnessConfirmation'};
        if (defined $pregnancyConfirmation) {
            $pregnancyConfirmation = unpack("N", pack("B32", substr("0" x 32 . $pregnancyConfirmation, -32)));
            $reports{$vaersId}->{'pregnancyConfirmation'} = $pregnancyConfirmation;
        }
        if (defined $pregnancySeriousnessConfirmation) {
            $pregnancySeriousnessConfirmation = unpack("N", pack("B32", substr("0" x 32 . $pregnancySeriousnessConfirmation, -32)));
            $reports{$vaersId}->{'pregnancySeriousnessConfirmation'} = $pregnancySeriousnessConfirmation;
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
        seriousnessConfirmation,
        seriousnessConfirmationRequired,
        seriousnessConfirmationTimestamp,
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
my $total     = keys %$rTb;
my $current   = 0;
my $restored  = 0;
my $sRestored = 0;
my $missing   = 0;
my $missingDeath   = 0;
my $missingSerious = 0;
my @deletedReports = ();
for my $vaersId (sort{$a <=> $b} keys %$rTb) {
    my $pregnancyConfirmationRequired       = %$rTb{$vaersId}->{'pregnancyConfirmationRequired'}   // die;
    $pregnancyConfirmationRequired          = unpack("N", pack("B32", substr("0" x 32 . $pregnancyConfirmationRequired, -32)));
    my $pregnancyConfirmation               = %$rTb{$vaersId}->{'pregnancyConfirmation'};
    my $pregnancyConfirmationTimestamp      = %$rTb{$vaersId}->{'pregnancyConfirmationTimestamp'};
    my $seriousnessConfirmationRequired     = %$rTb{$vaersId}->{'seriousnessConfirmationRequired'} // die;
    $seriousnessConfirmationRequired        = unpack("N", pack("B32", substr("0" x 32 . $seriousnessConfirmationRequired, -32)));
    my $seriousnessConfirmation             = %$rTb{$vaersId}->{'seriousnessConfirmation'};
    my $seriousnessConfirmationTimestamp    = %$rTb{$vaersId}->{'seriousnessConfirmationTimestamp'};
    my $childDied                           = %$rTb{$vaersId}->{'childDied'}                       // die;
    $childDied                              = unpack("N", pack("B32", substr("0" x 32 . $childDied, -32)));
    my $childSeriousAE                      = %$rTb{$vaersId}->{'childSeriousAE'}                  // die;
    $childSeriousAE                         = unpack("N", pack("B32", substr("0" x 32 . $childSeriousAE, -32)));
    $current++;
    if (defined $pregnancyConfirmation && !exists $reports{$vaersId}->{'pregnancyConfirmation'}) {
        $pregnancyConfirmation = unpack("N", pack("B32", substr("0" x 32 . $pregnancyConfirmation, -32)));
        $pregnancyConfirmationTimestamp = 'UNIX_TIMESTAMP()' unless defined $pregnancyConfirmationTimestamp;
        my $reportId = $reports{$vaersId}->{'reportId'};
        unless ($reportId) {
            $missing++;
            my $aEDescription   = %$rTb{$vaersId}->{'aEDescription'}  // die;
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
                pregnancyConfirmation          = $pregnancyConfirmation,
                pregnancyConfirmationTimestamp = $pregnancyConfirmationTimestamp,
                pregnancyConfirmationUserId    = 1,
                childDied                      = $childDied,
                childSeriousAE                 = $childSeriousAE
            WHERE id = $reportId");
        $sth->execute(
        ) or die $sth->err();
    }
    if (defined $seriousnessConfirmation && !exists $reports{$vaersId}->{'pregnancySeriousnessConfirmation'}) {
        $seriousnessConfirmation = unpack("N", pack("B32", substr("0" x 32 . $seriousnessConfirmation, -32)));
        $seriousnessConfirmationTimestamp = 'UNIX_TIMESTAMP()' unless defined $seriousnessConfirmationTimestamp;
        my $reportId = $reports{$vaersId}->{'reportId'};
        $sRestored++;
        my $sth = $dbh->prepare("
            UPDATE report SET
                pregnancySeriousnessConfirmation          = $seriousnessConfirmation,
                pregnancySeriousnessConfirmationTimestamp = $seriousnessConfirmationTimestamp,
                childDied                                 = $childDied,
                childSeriousAE                            = $childSeriousAE,
                pregnancySeriousnessConfirmationUserId    = 1
            WHERE id = $reportId");
        $sth->execute(
        ) or die $sth->err();
    }
    # say "[$current / $total] - restored [$restored] - seriousness restored [$sRestored] - missing [$missing] ($missingDeath | $missingSerious)";
}
say "[$current / $total] - restored [$restored] - seriousness restored [$sRestored] - missing [$missing] ($missingDeath | $missingSerious)";
open my $out, '>:utf8', 'deleted_reports.json';
say $out encode_json\@deletedReports;
close $out;