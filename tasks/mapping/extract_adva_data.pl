#!/usr/bin/perl
use strict;
use warnings;
use v5.26;
use Data::Dumper;
use Data::Printer;
binmode STDOUT, ":utf8";
use utf8;
use open ':std', ':encoding(UTF-8)';
no autovivification;
use utf8;
use JSON;
use Text::CSV qw( csv );
use Encode;
use Encode::Unicode;
use Math::Round qw(nearest);
use FindBin;
use lib "$FindBin::Bin/../../lib";
use time;

my $advaFile   = "raw_data/pfizer_trials/adva.csv";
open my $in, '<:utf8', $advaFile;
my $dataCsv    = Text::CSV_XS->new ({ binary => 1 });
my %dataLabels = ();
my ($dRNum,
	$expectedValues) = (0, 0);
my %subjects   = ();
while (<$in>) {
	$dRNum++;

	# Verifying line.
	my $line = $_;
	$line = decode("ascii", $line);
	for (/[^\n -~]/g) {
	    printf "Bad character: %02x\n", ord $_;
	    die;
	}

	# First row = line labels.
	if ($dRNum == 1) {
		my @labels = split ',', $line;
		my $lN = 0;
		for my $label (@labels) {
			$label =~ s/\"//g;
			$dataLabels{$lN} = $label;
			$lN++;
		}
		$expectedValues = keys %dataLabels;
	} else {

		# Verifying we have the expected number of values.
		open my $fh, "<", \$_;
		my $row = $dataCsv->getline ($fh);
		my @row = @$row;
		die scalar @row . " != $expectedValues" unless scalar @row == $expectedValues;
		my $vN  = 0;
		my %values = ();
		for my $value (@row) {
			my $label = $dataLabels{$vN} // die;
			$values{$label} = $value;
			$vN++;
		}
		p%values;
		die;

		# Fetching the data we currently focus on.
		my $subjectId  = $values{'SUBJID'}  // die;
		my $uSubjectId = $values{'USUBJID'} // die;
		my $siteId     = $values{'SITEID'} // die;
		my $age        = $values{'AGE'}    // die;
		my $ageUnit    = $values{'AGEU'}   // die;
		my $phase      = $values{'PHASE'}  // die;
		my $isDtc      = $values{'ISDTC'}  // die;
		die unless $ageUnit eq 'YEARS';
		my ($siteCode) = $uSubjectId =~ /........ (....) ......../;
		# say "$siteCode != $siteId" unless $siteCode eq $siteId;
		$subjects{$uSubjectId}->{'phase'}     = $phase;
		$subjects{$uSubjectId}->{'siteId'}    = $siteId;
		$subjects{$uSubjectId}->{'subjectId'} = $subjectId;
		$subjects{$uSubjectId}->{'age'}       = $age;
		$subjects{$uSubjectId}->{'isDtc'}     = $isDtc;
		$subjects{$uSubjectId}->{'total'}++;
		# p$subjects{$uSubjectId};
		# say "uSubjectId : $uSubjectId";
		# say "isDtc      : $isDtc";
		# die;
		# die;
	}
}
close $in;
say "dRNum    : $dRNum";
say "patients : " . keys %subjects;