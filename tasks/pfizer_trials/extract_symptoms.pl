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

my $dt19600101   = '1960-01-01 12:00:00';
my $tp19600101   = time::datetime_to_timestamp($dt19600101);
my $symptomsFile = "raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0663135-0671344-125742_S1_M5_c4591001-A-D-adsympt.csv";
die "you must convert the symptoms file using readstats and place it in [raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0663135-0671344-125742_S1_M5_c4591001-A-D-adsympt.csv] first." unless -f $symptomsFile;
open my $in, '<:utf8', $symptomsFile;
my $dataCsv      = Text::CSV_XS->new ({ binary => 1 });
my %dataLabels   = ();
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
		# p%values;
		# die;
		my $parCat1 = $values{'PARCAT1'} // next;
		next unless $parCat1 eq 'SIGNS AND SYMPTOMS OF DISEASE';
		my $param = $values{'PARAM'} // die;
		my $value = $values{'AVALC'} // die;
		my $adt   = $values{'ADT'}   // die;
		next unless $adt;
		$adt            = $tp19600101 + $adt * 86400;
		my $adtDatetime = time::timestamp_to_datetime($adt);
		my $uSubjectId = $values{'USUBJID'} // die;
		my ($subjectId) = $uSubjectId =~ /^C4591001 .... (.*)$/;
		die unless $subjectId && $subjectId =~ /^........$/;
		# say "adtDatetime : $adtDatetime";
		# say "param       : $param";
		# say "value       : $value";
		$subjects{$subjectId}->{'subjectId'}     = $subjectId;
		$subjects{$subjectId}->{'uSubjectId'}    = $uSubjectId;
		$subjects{$subjectId}->{'uSubjectIds'}->{$uSubjectId} = 1;
		$subjects{$subjectId}->{'symptoms'}->{$adtDatetime}->{$param} = $value;
		# die;

		# Fetching the data we currently focus on.
		# p%values;
		# die;

	}
}

say "dRNum       : $dRNum";
say "patients    : " . keys %subjects;

my $outputFolder   = "public/doc/pfizer_trials";
make_path($outputFolder) unless (-d $outputFolder);

# Prints patients JSON.
open my $out, '>:utf8', "$outputFolder/pfizer_patients_symptoms.json";
print $out encode_json\%subjects;
close $out;