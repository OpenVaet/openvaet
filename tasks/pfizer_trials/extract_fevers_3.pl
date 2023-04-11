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
my $aeFile     = "raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0149082-to-0158559_125742_S1_M5_c4591001-S-D-ce.csv";
die "you must convert the ae file using readstats and place it in [raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0149082-to-0158559_125742_S1_M5_c4591001-S-D-ce.csv] first." unless -f $aeFile;
open my $in, '<:utf8', $aeFile;
my $dataCsv    = Text::CSV_XS->new ({ binary => 1 });
my %dataLabels = ();
my ($dRNum,
	$expectedValues,
	$noVisitName,
	$noVisitDate) = (0, 0, 0, 0);
my %subjects   = ();
my %stats      = ();
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

		my $ceTerm      = $values{'CETERM'}  // die;
		# p%values;
		# die if $ceTerm eq 'FEVER';
		my $ceStartDate = $values{'CEDTC'}   // die;
		unless ($ceStartDate) {
			$ceStartDate = $values{'CERFTDTC'} // die;
			$stats{'hasDate'}->{'CERFTDTC'}++ if $ceStartDate;
		} else {
			$stats{'hasDate'}->{'CEDTC'}++;
		}
		$ceStartDate    =~ s/\D//g;
		my $ceSeverity  = $values{'CESEV'}   // die;
		my $uSubjectId  = $values{'USUBJID'} // die;
		my ($subjectId) = $uSubjectId =~ /^C4591001 .... (.*)$/;
		die unless $subjectId && $subjectId =~ /^........$/;
		die unless $uSubjectId =~ /$subjectId$/;
		unless ($ceStartDate) {
			$stats{'noDate'}->{$ceTerm}++;
			# p%values;
			if ($ceTerm eq 'FEVER') {
				p%values;
				die;
			}
			next;
		}
		$stats{'hasDate'}->{'total'}++;
		# p%values;
		# die;
		# die if $ceTerm eq 'FEVER';
		# say "ceTerm      : $ceTerm";
		# say "ceStartDate : $ceStartDate";
		# say "ceSeverity  : $ceSeverity";
		my $dayAfterDose  = $values{'CETPT'}  // die;
		my $afterShot  = $values{'CETPTREF'}  // die;
		$subjects{$subjectId}->{'aeListed'}->{$ceStartDate}->{$ceTerm}->{'severity'} = $ceSeverity;
		$subjects{$subjectId}->{'aeListed'}->{$ceStartDate}->{$ceTerm}->{'dayAfterDose'} = $dayAfterDose;
		$subjects{$subjectId}->{'aeListed'}->{$ceStartDate}->{$ceTerm}->{'afterShot'} = $afterShot;
		$subjects{$subjectId}->{'totalSDCeRows'}++;
	}
}
close $in;
$dRNum--;

p%stats;
say "dRNum       : $dRNum";
say "patients    : " . keys %subjects;

my $outputFolder   = "public/doc/pfizer_trials";
make_path($outputFolder) unless (-d $outputFolder);

# Prints patients JSON.
open my $out, '>:utf8', "$outputFolder/S1_M5_c4591001-S-D-ce.json";
print $out encode_json\%subjects;
close $out;