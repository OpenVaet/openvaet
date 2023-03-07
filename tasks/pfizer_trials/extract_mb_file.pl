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
use Scalar::Util qw(looks_like_number);
use Math::Round qw(nearest);
use File::Path qw(make_path);
use FindBin;
use lib "$FindBin::Bin/../../lib";
use time;

my $dt19600101 = '1960-01-01 12:00:00';
my $tp19600101 = time::datetime_to_timestamp($dt19600101);
my $mbFile     = "raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0282366-to-0285643_125742_S1_M5_c4591001-S-D-mb.csv";
die "you must convert the mb file using readstats and place it in [raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0282366-to-0285643_125742_S1_M5_c4591001-S-D-mb.csv] first." unless -f $mbFile;
open my $in, '<:utf8', $mbFile;
my $dataCsv    = Text::CSV_XS->new ({ binary => 1 });
my %dataLabels = ();
my ($dRNum,
	$expectedValues,
	$noVisitName,
	$noVisitDate) = (0, 0, 0, 0);
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
		# die;

		# Fetching the data we currently focus on.
		# p%values;
		# die;
		my $uSubjectId  = $values{'USUBJID'}  // die;
		my ($subjectId) = $uSubjectId =~ /^C4591001 .... (.*)$/;
		die unless $subjectId && $subjectId =~ /^........$/;
		my $mbDatetime  = $values{'MBDTC'}    // die;
		$mbDatetime     =~ s/T/ /;
		my ($mbDate, $mbHour) = split ' ', $mbDatetime;

		# Skipping the only row without identified data (11341369 V102_VAX4 NASAL_SWAB NOT DONE).
		unless ($mbDate) {
			$noVisitDate++;
			next;
		}
		my $mbName      = $values{'MBNAM'}    // die;
		my $mbOrres     = $values{'MBORRES'}  // die;
		my $visit       = $values{'VISIT'}    // die;
		my $mbMethod    = $values{'MBMETHOD'} // die;
		my $mbTest      = $values{'MBTEST'}   // die;
		my $mbStat      = $values{'MBSTAT'}   // die;
		my $spDevId     = $values{'SPDEVID'}  // die;
		unless ($visit) {
			p%values;
			$noVisitName++;
			next;
		}
		die unless $mbTest;
		unless ($mbOrres) {
			die unless $mbStat && $mbStat eq 'NOT DONE';
		}
		$subjects{$subjectId}->{'subjectId'}  = $subjectId;
		$subjects{$subjectId}->{'uSubjectId'} = $uSubjectId;
		$subjects{$subjectId}->{'uSubjectIds'}->{$uSubjectId} = 1;
		$subjects{$subjectId}->{'mbVisits'}->{$mbDate}->{'visit'} = $visit;
		if ($mbHour) {
			$subjects{$subjectId}->{'mbVisits'}->{$mbDate}->{'visitHour'} = $mbHour;
			if (exists $subjects{$subjectId}->{'mbVisits'}->{$mbDate}->{'visitHour'}) {
				die unless $subjects{$subjectId}->{'mbVisits'}->{$mbDate}->{'visitHour'} eq $mbHour;
			}
		}
		$subjects{$subjectId}->{'mbVisits'}->{$mbDate}->{$mbTest}->{'spDevId'}  = $spDevId;
		$subjects{$subjectId}->{'mbVisits'}->{$mbDate}->{$mbTest}->{'mbStat'}   = $mbStat;
		$subjects{$subjectId}->{'mbVisits'}->{$mbDate}->{$mbTest}->{'mbResult'} = $mbOrres;
		$subjects{$subjectId}->{'mbVisits'}->{$mbDate}->{$mbTest}->{'mbMethod'} = $mbMethod;
		$subjects{$subjectId}->{'mbVisits'}->{$mbDate}->{$mbTest}->{'mbName'}   = $mbName;
		$subjects{$subjectId}->{'totalMbRows'}++;
		# p$subjects{$uSubjectId};
		# p%values;
		# p%subjects;
		# die;
		# last if $dRNum > 100;
		# say "uSubjectId : $uSubjectId";
		# say "isDtc      : $isDtc";
		# die;
		# die;
	}
}
close $in;
say "dRNum       : $dRNum";
say "patients    : " . keys %subjects;
say "noVisitName : $noVisitName";
say "noVisitDate : $noVisitDate";

my $outputFolder   = "public/doc/pfizer_trials";
make_path($outputFolder) unless (-d $outputFolder);

# Prints patients JSON.
open my $out, '>:utf8', "$outputFolder/pfizer_mb_patients.json";
print $out encode_json\%subjects;
close $out;