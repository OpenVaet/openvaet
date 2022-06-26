#!/usr/bin/perl
use strict;
use warnings;
use 5.30.0;
no autovivification;
binmode STDOUT, ":utf8";
use utf8;
use Data::Printer;
use Data::Dumper;
use File::Path qw(make_path);
use Text::CSV qw( csv );
use Math::Round qw(nearest);
use Encode;
use Encode::Unicode;
use JSON;
use FindBin;
use Scalar::Util qw(looks_like_number);
use File::stat;
use lib "$FindBin::Bin/../../../lib";

# Project's libraries.
use config;
use global;
use time;

open my $out, '>:utf8', 'vaers_report_pregnancies.csv';
my $tb = $dbh->selectall_hashref("
	SELECT
		id as reportId,
		vaersId,
		pregnancyConfirmation,
		pregnancyConfirmationTimestamp,
		pregnancyConfirmationRequired,
		menstrualCycleDisordersConfirmation,
		menstrualCycleDisordersConfirmationTimestamp,
		menstrualCycleDisordersConfirmationRequired
	FROM ccot_report
	WHERE pregnancyConfirmation IS NOT NULL", 'reportId');
for my $reportId (sort{$a <=> $b} keys %$tb) {
	my $vaersId                        = %$tb{$reportId}->{'vaersId'}                       // die;
	my $pregnancyConfirmation          = %$tb{$reportId}->{'pregnancyConfirmation'}         // die;
	my $pregnancyConfirmationRequired  = %$tb{$reportId}->{'pregnancyConfirmationRequired'} // die;
    $pregnancyConfirmation             = unpack("N", pack("B32", substr("0" x 32 . $pregnancyConfirmation, -32)));
    $pregnancyConfirmationRequired     = unpack("N", pack("B32", substr("0" x 32 . $pregnancyConfirmationRequired, -32)));
	my $menstrualCycleDisordersConfirmation          = %$tb{$reportId}->{'menstrualCycleDisordersConfirmation'}         // die;
	my $menstrualCycleDisordersConfirmationRequired  = %$tb{$reportId}->{'menstrualCycleDisordersConfirmationRequired'} // die;
    $menstrualCycleDisordersConfirmation             = unpack("N", pack("B32", substr("0" x 32 . $menstrualCycleDisordersConfirmation, -32)));
    $menstrualCycleDisordersConfirmationRequired     = unpack("N", pack("B32", substr("0" x 32 . $menstrualCycleDisordersConfirmationRequired, -32)));
	my $pregnancyConfirmationTimestamp = %$tb{$reportId}->{'pregnancyConfirmationTimestamp'} // die;
	my $menstrualCycleDisordersConfirmationTimestamp = %$tb{$reportId}->{'menstrualCycleDisordersConfirmationTimestamp'} // die;
	print $out "$vaersId;$pregnancyConfirmation;$pregnancyConfirmationTimestamp;$pregnancyConfirmationRequired;$menstrualCycleDisordersConfirmation;$menstrualCycleDisordersConfirmationTimestamp;$menstrualCycleDisordersConfirmationRequired;\n";
}
close $out;