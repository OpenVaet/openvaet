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
my $aeFile     = "raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0763794-0764725-125742_S1_M5_c4591001-A-Supp-D-adae-supp.csv";
die "you must convert the ae file using readstats and place it in [raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0763794-0764725-125742_S1_M5_c4591001-A-Supp-D-adae-supp.csv] first." unless -f $aeFile;
open my $in, '<:utf8', $aeFile;
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

		# Verifying we have the expected nuaeer of values.
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
		die unless $uSubjectId =~ /$subjectId$/;
		my $aeDatetime  = $values{'AESTDTC'}    // die;
		$aeDatetime     =~ s/T/ /;
		my ($aeDate, $aeHour) = split ' ', $aeDatetime;

		# Skipping the only row without identified data (11341369 V102_VAX4 NASAL_SWAB NOT DONE).
		unless ($aeDate) {
			$noVisitDate++;
			next;
		}
		my $aeLlt       = $values{'AELLT'}    // die;
		my $aeRelTxt    = $values{'AERELTXT'} // die;
		my $aeRel       = $values{'AEREL'}    // die;
		$subjects{$subjectId}->{'subjectId'}     = $subjectId;
		$subjects{$subjectId}->{'uSubjectId'}    = $uSubjectId;
		$subjects{$subjectId}->{'uSubjectIds'}->{$uSubjectId} = 1;
		if ($aeHour) {
			$subjects{$subjectId}->{'aeListed'}->{$aeDate}->{'visitHour'} = $aeHour;
			if (exists $subjects{$subjectId}->{'aeListed'}->{$aeDate}->{'visitHour'}) {
				die unless $subjects{$subjectId}->{'aeListed'}->{$aeDate}->{'visitHour'} eq $aeHour;
			}
		}
		$subjects{$subjectId}->{'aeListed'}->{$aeDate}->{$aeLlt}->{'aeRel'}    = $aeRel;
		$subjects{$subjectId}->{'aeListed'}->{$aeDate}->{$aeLlt}->{'aeRelTxt'} = $aeRelTxt;
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
open my $out, '>:utf8', "$outputFolder/pfizer_ae_patients.json";
print $out encode_json\%subjects;
close $out;