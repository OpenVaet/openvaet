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
my $faceFile = "raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0539816-0593326-125742_S1_M5_c4591001-01-S-Supp-D-face.csv";
die "you must convert the face file using readstats and place it in [raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0539816-0593326-125742_S1_M5_c4591001-01-S-Supp-D-face.csv] first." unless -f $faceFile;
open my $in, '<:utf8', $faceFile;
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

		# Fetching the data we currently focus on.
		my $uSubjectId        = $values{'USUBJID'} // die;
		my ($subjectId)       = $uSubjectId =~ /^C4591001 .... (.*)$/;
		die unless $subjectId && $subjectId =~ /^........$/;
		my $visitName = $values{'VISIT'}    // die;
		my $visitDate = $values{'FADTC'}    // die;
		my $faTest    = $values{'FATEST'}   // die;
		my $fastResc  = $values{'FASTRESC'} // die;
		if (
			$faTest eq 'First Symptom Date' ||
			$faTest eq 'Last Symptom Resolved Date'
		) {
			$subjects{$subjectId}->{$visitDate}->{'visitName'}     = $visitName;
			$subjects{$subjectId}->{$visitDate}->{'symptomsDates'}->{$faTest} = $fastResc;
		} elsif (
			$faTest eq 'Severity/Intensity' ||
			$faTest eq 'Occurrence Indicator' ||
			$faTest eq 'Related to Study Treatment' ||
			$faTest eq 'Stop Date Meds Given to Trt/Pnt Symptoms' ||
			$faTest eq 'Medication to Treat Fever or Pain' ||
			$faTest eq 'Diameter' ||
			$faTest eq 'Minimum Diameter' ||
			$faTest eq 'Maximum Diameter' ||
			$faTest eq 'Symptom Ongoing' ||
			$faTest eq 'Grade 4 Criteria Met'
		) {
			$dRNum--;
		} else {
			die "faTest : [$faTest]";
		}
	}
}
close $in;
say "dRNum           : $dRNum";
say "patients        : " . keys %subjects;

my $outputFolder   = "public/doc/pfizer_trials";
make_path($outputFolder) unless (-d $outputFolder);

# Prints patients JSON.
open my $out, '>:utf8', "$outputFolder/pfizer_face_patients.json";
print $out encode_json\%subjects;
close $out;