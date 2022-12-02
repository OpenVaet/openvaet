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
my $advaFile   = "raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0123168-to-0126026_125742_S1_M5_c4591001-A-D-adva.csv";
die "you must convert the adva file using readstats and place it in [raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0123168-to-0126026_125742_S1_M5_c4591001-A-D-adva.csv] first." unless -f $advaFile;
open my $in, '<:utf8', $advaFile;
my $dataCsv    = Text::CSV_XS->new ({ binary => 1 });
my %dataLabels = ();
my ($dRNum,
	$expectedValues,
	$noDose1Data) = (0, 0, 0);
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
		my $subjectId   = $values{'SUBJID'}  // die;
		my $uSubjectId  = $values{'USUBJID'} // die;
		my $trialSiteId = $values{'SITEID'}  // die;
		my $adt         = $values{'ADT'}     // die;
		$adt            = $tp19600101 + $adt * 86400;
		my $adtDatetime = time::timestamp_to_datetime($adt);
		my $age         = $values{'AGE'}     // die;
		my $sex         = $values{'SEX'}     // die;
		($age) = split '\.', $age;
		my $ageUnit     = $values{'AGEU'}    // die;
		die unless $ageUnit eq 'YEARS';
		my $phase       = $values{'PHASE'}   // die;
		my $isDtc       = $values{'ISDTC'}   // die;
		my $actArm      = $values{'ACTARM'}  // die;
		my $param       = $values{'PARAM'}   // die;
		my $avaLc       = $values{'AVALC'}   // die;
		my ($siteCode)  = $uSubjectId =~ /........ (....) ......../;
		# say "$siteCode != $trialSiteId" unless $siteCode eq $trialSiteId;
		# say "uSubjectId                 : $uSubjectId";
		# say "1 - randomizationTimestamp : $randomizationTimestamp";
		my $dose1Timestamp = $values{'TRTSDTM'} // die;
		unless (looks_like_number $dose1Timestamp) {
			# say "No randomization data";
			$noDose1Data++;
			next;
			p%values;
			die "dose1Timestamp : [$dose1Timestamp]";
		}
		my $dose1Datetime  = time::sas_timestamp_to_datetime($dose1Timestamp);
		# say "--> dose1Datetime  : $dose1Datetime";
		# say "--> dose1Datetime          : $dose1Datetime";
		my $dose2Timestamp = $values{'TR01EDTM'} // die;

		my ($dose2Datetime);
		if ($dose2Timestamp && $dose2Timestamp ne $dose1Timestamp) {
			$dose2Datetime = time::sas_timestamp_to_datetime($dose2Timestamp);
			# p%values;
			# say "--> dose2Datetime  : $dose2Datetime";
		}
		# die;
		if (exists $subjects{$subjectId}->{'dose1Datetime'}) {
			die unless $dose1Datetime eq $subjects{$subjectId}->{'dose1Datetime'};
		}
		if (exists $subjects{$subjectId}->{'dose1Datetime'}) {
			die unless $dose1Datetime eq $subjects{$subjectId}->{'dose1Datetime'};
		}
		if (exists $subjects{$subjectId}->{'dose2Datetime'} && $subjects{$subjectId}->{'dose2Datetime'}) {
			die unless $dose2Datetime eq $subjects{$subjectId}->{'dose2Datetime'};
		}
		$subjects{$subjectId}->{'actArm'}        = $actArm;
		$subjects{$subjectId}->{'phase'}         = $phase;
		$subjects{$subjectId}->{'param'}         = $param;
		$subjects{$subjectId}->{'trialSiteId'}   = $trialSiteId;
		$subjects{$subjectId}->{'subjectId'}     = $subjectId;
		$subjects{$subjectId}->{'uSubjectId'}    = $uSubjectId;
		$subjects{$subjectId}->{'uSubjectIds'}->{$uSubjectId} = 1;
		$subjects{$subjectId}->{'sex'}           = $sex;
		$subjects{$subjectId}->{'age'}           = $age;
		$subjects{$subjectId}->{'isDtc'}         = $isDtc;
		$subjects{$subjectId}->{'dose1Datetime'} = $dose1Datetime;
		$subjects{$subjectId}->{'dose2Datetime'} = $dose2Datetime;
		$subjects{$subjectId}->{'visits'}->{$adtDatetime}->{$param} = $avaLc;
		$subjects{$subjectId}->{'totalAdvaRows'}++;
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
say "noDose1Data : $noDose1Data";
say "patients    : " . keys %subjects;

my $outputFolder   = "public/doc/pfizer_trials";
make_path($outputFolder) unless (-d $outputFolder);

# Prints patients JSON.
open my $out, '>:utf8', "$outputFolder/pfizer_adva_patients.json";
print $out encode_json\%subjects;
close $out;