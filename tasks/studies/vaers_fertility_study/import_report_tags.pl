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

open my $in, '<:utf8', 'vaers_report_pregnancies.csv';
while (<$in>) {
	my ($vaersId, $pregnancyConfirmation, $pregnancyConfirmationTimestamp, $pregnancyConfirmationRequired, $menstrualCycleDisordersConfirmation, $menstrualCycleDisordersConfirmationTimestamp, $menstrualCycleDisordersConfirmationRequired) = split ';', $_;
	# say "$vaersId, $pregnancyConfirmation, $pregnancyConfirmationTimestamp, $pregnancyConfirmationRequired";
	if ($pregnancyConfirmation) {
		my $sth = $dbh->prepare("UPDATE vaers_report SET pregnancyConfirmation = $pregnancyConfirmation, pregnancyConfirmationTimestamp = $pregnancyConfirmationTimestamp, pregnancyConfirmationRequired = $pregnancyConfirmationRequired WHERE vaersId = '$vaersId'");
		$sth->execute() or die $sth->err();
		# die;
	} else {
		my $sth = $dbh->prepare("UPDATE vaers_report SET menstrualCycleDisordersConfirmation = $menstrualCycleDisordersConfirmation, menstrualCycleDisordersConfirmationTimestamp = $menstrualCycleDisordersConfirmationTimestamp, menstrualCycleDisordersConfirmationRequired = $menstrualCycleDisordersConfirmationRequired WHERE vaersId = '$vaersId'");
		$sth->execute() or die $sth->err();
		# die;
	}
}
close $in;