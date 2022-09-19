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
    my $tb = $dbh->selectall_hashref("SELECT id as reportId, vaersId, patientAgeConfirmation FROM report", 'reportId');
    for my $reportId (sort{$a <=> $b} keys %$tb) {
        my $vaersId                = %$tb{$reportId}->{'vaersId'};
        my $patientAgeConfirmation = %$tb{$reportId}->{'patientAgeConfirmation'};
        if ($patientAgeConfirmation) {
            $patientAgeConfirmation    = unpack("N", pack("B32", substr("0" x 32 . $patientAgeConfirmation, -32)));
            $reports{$vaersId}->{'patientAgeConfirmation'} = $patientAgeConfirmation;
        }
        $reports{$vaersId}->{'reportId'} = $reportId;
    }
}

my @tables = ('vaers_deaths_report', 'vaers_foreign_report');
for my $table (@tables) {
    my $sql = "
        SELECT
            vaersId,
            patientAgeConfirmation,
            patientAgeConfirmationRequired,
            patientAgeConfirmationTimestamp,
            userId as patientAgeUserId,
            patientAgeFixed,
            vaersSexFixed as sexFixed,
            vaccinationDateFixed,
            onsetDateFixed,
            deceasedDateFixed,
            hoursBetweenVaccineAndAE,
            patientDiedFixed,
            lifeThreatningFixed,
            permanentDisabilityFixed,
            hospitalizedFixed,
            patientAgeConfirmationTimestamp
        FROM $table WHERE patientAgeConfirmationRequired = 1";
    say "$sql";
    my $rTb                 = $dbh->selectall_hashref($sql, 'vaersId'); # ORDER BY RAND()
    my $total = keys %$rTb;
    my $current = 0;
    for my $vaersId (sort{$a <=> $b} keys %$rTb) {
        my $patientDiedFixed       = %$rTb{$vaersId}->{'patientDiedFixed'} // die;
        $patientDiedFixed          = unpack("N", pack("B32", substr("0" x 32 . $patientDiedFixed, -32)));
        my $lifeThreatningFixed       = %$rTb{$vaersId}->{'lifeThreatningFixed'} // die;
        $lifeThreatningFixed          = unpack("N", pack("B32", substr("0" x 32 . $lifeThreatningFixed, -32)));
        my $permanentDisabilityFixed       = %$rTb{$vaersId}->{'permanentDisabilityFixed'} // die;
        $permanentDisabilityFixed          = unpack("N", pack("B32", substr("0" x 32 . $permanentDisabilityFixed, -32)));
        my $hospitalizedFixed       = %$rTb{$vaersId}->{'hospitalizedFixed'} // die;
        $hospitalizedFixed          = unpack("N", pack("B32", substr("0" x 32 . $hospitalizedFixed, -32)));
        my $patientAgeConfirmationRequired       = %$rTb{$vaersId}->{'patientAgeConfirmationRequired'} // die;
        $patientAgeConfirmationRequired          = unpack("N", pack("B32", substr("0" x 32 . $patientAgeConfirmationRequired, -32)));
        my $patientAgeConfirmation               = %$rTb{$vaersId}->{'patientAgeConfirmation'};
        $patientAgeConfirmation                  = unpack("N", pack("B32", substr("0" x 32 . $patientAgeConfirmation, -32)));
        my $patientAgeConfirmationTimestamp      = %$rTb{$vaersId}->{'patientAgeConfirmationTimestamp'};
        my $patientAgeFixed       = %$rTb{$vaersId}->{'patientAgeFixed'};
        my $sexFixed       = %$rTb{$vaersId}->{'sexFixed'};
        my $vaccinationDateFixed       = %$rTb{$vaersId}->{'vaccinationDateFixed'};
        my $onsetDateFixed       = %$rTb{$vaersId}->{'onsetDateFixed'};
        my $deceasedDateFixed       = %$rTb{$vaersId}->{'deceasedDateFixed'};
        my $hoursBetweenVaccineAndAE       = %$rTb{$vaersId}->{'hoursBetweenVaccineAndAE'};
        my $patientAgeUserId       = %$rTb{$vaersId}->{'patientAgeUserId'};
        $current++;
        say "[$current / $total]";
        if ($patientAgeConfirmation && !$reports{$vaersId}->{'patientAgeConfirmation'}) {
            my $reportId = $reports{$vaersId}->{'reportId'} // next;
            my $sth = $dbh->prepare("
                UPDATE report SET
                    patientAgeConfirmation = $patientAgeConfirmation,
                    patientAgeFixed = ?,
                    sexFixed = ?,
                    vaccinationDateFixed = ?,
                    onsetDateFixed = ?,
                    deceasedDateFixed = ?,
                    hoursBetweenVaccineAndAE = ?,
                    patientDiedFixed = $patientDiedFixed,
                    lifeThreatningFixed = $lifeThreatningFixed,
                    permanentDisabilityFixed = $permanentDisabilityFixed,
                    hospitalizedFixed = $hospitalizedFixed,
                    patientAgeConfirmationTimestamp = $patientAgeConfirmationTimestamp,
                    patientAgeUserId = ?
                WHERE id = $reportId");
            $sth->execute(
                $patientAgeFixed,
                $sexFixed,
                $vaccinationDateFixed,
                $onsetDateFixed,
                $deceasedDateFixed,
                $hoursBetweenVaccineAndAE,
                $patientAgeUserId
            ) or die $sth->err();
        }
    }
}