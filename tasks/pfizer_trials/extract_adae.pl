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

my $dt19600101  = '1960-01-01 12:00:00';
my $tp19600101  = time::datetime_to_timestamp($dt19600101);
my $adaeFile = "raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0774873-0775804_125742_S1_M5_C4591001-A-D_adae.csv";
die "you must convert the adae file using readstats and place it in [raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0774873-0775804_125742_S1_M5_C4591001-A-D_adae.csv] first." unless -f $adaeFile;
open my $in, '<:utf8', $adaeFile;
my $dataCsv     = Text::CSV_XS->new ({ binary => 1 });
my %dataLabels  = ();
my ($dRNum,
	$expectedValues) = (0, 0);
my %subjects    = ();
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
		# open my $out, '>:utf8', 'sample_ae.json';
		# print $out encode_json\%values;
		# close $out;
		# p%values;
		# die;

		# Fetching the data we currently focus on.
		my $subjectId         = $values{'SUBJID'}   // die;
		my $uSubjectId        = $values{'USUBJID'}  // die;
		my $vPhase            = $values{'VPHASE'}   // die;
		my $aperiodDc         = $values{'APERIODC'} // die;
		my $relation          = $values{'AREL'}     // die;
		my $aehlgt            = $values{'AEHLGT'}   // die;
		my $aehlt             = $values{'AEHLT'}    // die;
		my $aeser             = $values{'AESER'}    // die;
		my $aeRelTxt          = $values{'AERELTXT'} // die;
		my $toxicityGrade     = $values{'ATOXGR'}   // die;
		$toxicityGrade        =~ s/GRADE //;
		my $aeStdDt           = $values{'AESTDTC'}  // die;
		my $aeEndDt           = $values{'AEENDTC'}  // die;
		$aeStdDt              =~ s/T/ /;
		my $aeTerm            = $values{'AETERM'}   // die;
		$subjects{$subjectId}->{'totalADC19EFRows'}++;
		my $totalADC19EFRows     = $subjects{$subjectId}->{'totalADC19EFRows'} // die;
		$subjects{$subjectId}->{'uSubjectIds'}->{$uSubjectId} = 1;
		$subjects{$subjectId}->{'uSubjectId'} = $uSubjectId;
		my ($aeCompdate) = split ' ', $aeStdDt;
		$aeCompdate =~ s/\D//g;
		$subjects{$subjectId}->{'adverseEffects'}->{$aeCompdate}->{$aeTerm}->{'toxicityGrade'} = $toxicityGrade;
		$subjects{$subjectId}->{'adverseEffects'}->{$aeCompdate}->{$aeTerm}->{'aeStdDt'} = $aeStdDt;
		$subjects{$subjectId}->{'adverseEffects'}->{$aeCompdate}->{$aeTerm}->{'aehlgt'} = $aehlgt;
		$subjects{$subjectId}->{'adverseEffects'}->{$aeCompdate}->{$aeTerm}->{'aehlt'} = $aehlt;
		$subjects{$subjectId}->{'adverseEffects'}->{$aeCompdate}->{$aeTerm}->{'aeser'} = $aeser;
		$subjects{$subjectId}->{'adverseEffects'}->{$aeCompdate}->{$aeTerm}->{'aeRelTxt'} = $aeRelTxt;
		$subjects{$subjectId}->{'adverseEffects'}->{$aeCompdate}->{$aeTerm}->{'aeEndDt'} = $aeEndDt;
		$subjects{$subjectId}->{'adverseEffects'}->{$aeCompdate}->{$aeTerm}->{'aperiodDc'} = $aperiodDc;
		$subjects{$subjectId}->{'adverseEffects'}->{$aeCompdate}->{$aeTerm}->{'relation'} = $relation;
		$subjects{$subjectId}->{'adverseEffects'}->{$aeCompdate}->{$aeTerm}->{'vPhase'} = $vPhase;
		# p$subjects{$subjectId};
		# die;
	}
}
close $in;
say "dRNum           : $dRNum";
say "patients        : " . keys %subjects;

my $outputFolder   = "public/doc/pfizer_trials";
make_path($outputFolder) unless (-d $outputFolder);

# Prints patients JSON.
open my $out, '>:utf8', "$outputFolder/pfizer_adae_patients.json";
print $out encode_json\%subjects;
close $out;