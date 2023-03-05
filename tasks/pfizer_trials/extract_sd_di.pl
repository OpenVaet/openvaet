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
my $diFile     = "raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0764726-125742_S1_M5_c4591001-S-D-di.csv";
die "you must convert the di file using readstats and place it in [raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0764726-125742_S1_M5_c4591001-S-D-di.csv] first." unless -f $diFile;
open my $in, '<:utf8', $diFile;
my $dataCsv    = Text::CSV_XS->new ({ binary => 1 });
my %dataLabels = ();
my ($dRNum,
	$expectedValues,
	$noVisitName,
	$noVisitDate) = (0, 0, 0, 0);
my %tests   = ();
while (<$in>) {
	$dRNum++;
	chomp $_;

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

		# Verifying we have the expected nudier of values.
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
		my $spDevId = $values{'SPDEVID'} // die;
		next unless $spDevId;
		my $diParm  = $values{'DIPARM'}  // die;
		my $diVal   = $values{'DIVAL'}   // die;
		$tests{$spDevId}->{$diParm} = $diVal;
	}
}
close $in;
say "dRNum       : $dRNum";
say "tests       : " . keys %tests;

my $outputFolder   = "public/doc/pfizer_trials";
make_path($outputFolder) unless (-d $outputFolder);

# Prints tests JSON.
open my $out, '>:utf8', "$outputFolder/pfizer_di.json";
print $out encode_json\%tests;
close $out;