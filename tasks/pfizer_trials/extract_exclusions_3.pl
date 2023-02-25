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
my $sdieFile = "raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0282329-to-0282365_125742_S1_M5_c4591001-S-D-ie.csv";
die "you must convert the sdie file using readstats and place it in [raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0282329-to-0282365_125742_S1_M5_c4591001-S-D-ie.csv] first." unless -f $sdieFile;
open my $in, '<:utf8', $sdieFile;
my $dataCsv     = Text::CSV_XS->new ({ binary => 1 });
my %dataLabels  = ();
my ($dRNum,
	$expectedValues,
	$moreThanOneRow) = (0, 0, 0);
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
		# p%values;
		# die;
		# next;

		# Fetching the data we currently focus on.
		my $uSubjectId        = $values{'USUBJID'} // die;
		my ($subjectId)       = $uSubjectId =~ /^C4591001 .... (.*)$/;
		die unless $subjectId && $subjectId =~ /^........$/;
		die unless $uSubjectId =~ /$subjectId$/;
		my $exclusionDate     = $values{'IEDTC'}   // die;
		my $motive            = $values{'IETEST'}  // die;
		my $category          = $values{'IECAT'}   // die;
		if (exists $subjects{$subjectId}) {
			# p $subjects{$subjectId};
			# p%values;
			$subjects{$subjectId}->{'moreThanOneRow'} = 1;
			$moreThanOneRow++;
		}
		$subjects{$subjectId}->{'totalSDieRows'}++;
		my $totalSDieRows     = $subjects{$subjectId}->{'totalSDieRows'} // die;
		$subjects{$subjectId}->{'exclusions'}->{$totalSDieRows}->{'category'}        = $category;
		$subjects{$subjectId}->{'exclusions'}->{$totalSDieRows}->{'exclusionDate'}   = $exclusionDate;
		$subjects{$subjectId}->{'exclusions'}->{$totalSDieRows}->{'motive'}          = $motive;
		$subjects{$subjectId}->{'uSubjectIds'}->{$uSubjectId} = 1;
		$subjects{$subjectId}->{'uSubjectId'} = $uSubjectId;
		# p$subjects{$subjectId};
		# die;
	}
}
close $in;
say "dRNum           : $dRNum";
say "patients        : " . keys %subjects;
say "moreThanOneRow  : $moreThanOneRow";

my $outputFolder   = "public/doc/pfizer_trials";
make_path($outputFolder) unless (-d $outputFolder);

# Prints patients JSON.
open my $out, '>:utf8', "$outputFolder/pfizer_sdie_patients.json";
print $out encode_json\%subjects;
close $out;