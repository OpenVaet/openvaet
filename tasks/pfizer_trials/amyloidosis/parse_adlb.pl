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
use lib "$FindBin::Bin/../../../lib";
use time;

my $dt19600101    = '1960-01-01 12:00:00';
my $tp19600101    = time::datetime_to_timestamp($dt19600101);
my $dataFolder    = 'raw_data/pfizer_trials/xpt_files_to_csv';
my $adlbFile      = "$dataFolder/FDA-CBER-2021-5683-0652981-0654506-125742_S1_M5_bnt162-01-A-D-adlb.csv";
my %subjects      = ();
my $dataCsv       = Text::CSV_XS->new ({ binary => 1 });
my %params = ();
parse_adlb();
# p%params;

sub parse_adlb {
	say "parsing ADLB ...";
	my %dataLabels    = ();
	my ($dRNum,
		$expectedValues,
		$noDose1Data) = (0, 0, 0);
	my $lastVisitNum  = 0;
	my $lastVisitName = 0;
	my $lastSubjectId = 0;
	open my $in, '<:utf8', $adlbFile;
	open my $outDouble, '>:utf8', 'double_tests_adlb.csv';
	while (<$in>) {
		$dRNum++;

		# Verifying line.
		chomp $_;
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

			# Fetching the data we currently focus on.
			my $subjectId   = $values{'SUBJID'}  // die;
			my $uSubjectId  = $values{'USUBJID'} // die;
			my $adt         = $values{'ADT'}     // die;
			$adt            = $tp19600101 + $adt * 86400;
			my $adtDatetime = time::timestamp_to_datetime($adt);
			my ($visitDate) = split ' ', $adtDatetime;
			$visitDate      =~ s/\D//g;
			my $age         = $values{'AGE'}     // die;
			my $sex         = $values{'SEX'}     // die;
			($age) = split '\.', $age;
			my $ageUnit     = $values{'AGEU'}    // die;
			die unless $ageUnit eq 'YEARS';
			my $aVisit      = $values{'AVISIT'}  // die;
			my $aVisitNum   = $values{'AVISITN'} // die;
			($aVisitNum)    = split '\.', $aVisitNum;
			my $cohort      = $values{'COHORT'}  // die;
			my $param       = $values{'PARAM'}   // die;
			$params{$param}++;
			my $avaLc       = $values{'AVALC'}   // die;
			my ($siteCode)  = $uSubjectId =~ /........ (....) ......../;
			# say "$siteCode != $trialSiteId" unless $siteCode eq $trialSiteId;
			# say "uSubjectId                 : $uSubjectId";
			# say "1 - randomizationTimestamp : $randomizationTimestamp";
			my $dose1Timestamp = $values{'TRTSDTM'} // die;
			unless (looks_like_number $dose1Timestamp) {
				say "No dose 1 data";
				$noDose1Data++;
				next;
				p%values;
				die "dose1Timestamp : [$dose1Timestamp]";
			}
			my $dose1Datetime  = time::sas_timestamp_to_datetime($dose1Timestamp);
			# say "--> dose1Datetime  : $dose1Datetime";
			# say "--> dose1Datetime          : $dose1Datetime";
			if (exists $subjects{$subjectId}->{'visits'}->{$aVisitNum}->{'tests'}->{$param}) {
				say $outDouble "$subjectId;$aVisitNum;$param;" . $subjects{$subjectId}->{'visits'}->{$aVisitNum}->{'tests'}->{$param};
			}
			if (
				$param eq 'COVID-19 S1 IgG (U/mL) - Luminex Immunoassay' ||
				$param eq 'SARS-CoV-2 serum neutralizing titer 50 (titer) - Virus Neutralization Assay' ||
				$param eq 'SARS-CoV-2 serum neutralizing titer 90 (titer) - Virus Neutralization Assay'
			) {
				# p%values;
				my %o = ();
				$o{'avaLc'}     = $avaLc;
				$o{'aVisit'}    = $aVisit;
				$o{'aVisitNum'} = $aVisitNum;
				if (!$aVisit) {
					die if exists $subjects{$subjectId}->{'visits'}->{$aVisitNum}->{'tests'}->{$param}; # This verifies that no incremental entry for the same test has
																										# been made before when the "AVISIT" scalar is empty.
				}
				push @{$subjects{$subjectId}->{'visits'}->{$aVisitNum}->{'tests'}->{$param}}, \%o;
			} else {
				$subjects{$subjectId}->{'visits'}->{$aVisitNum}->{'tests'}->{$param}  = $avaLc;
			}
			$subjects{$subjectId}->{'cohort'}          = $cohort;
			$subjects{$subjectId}->{'subjectId'}       = $subjectId;
			$subjects{$subjectId}->{'uSubjectId'}      = $uSubjectId;
			$subjects{$subjectId}->{'uSubjectIds'}->{$uSubjectId} = 1;
			$subjects{$subjectId}->{'sex'}             = $sex;
			$subjects{$subjectId}->{'age'}             = $age;
			$subjects{$subjectId}->{'dose1Datetime'}   = $dose1Datetime;
			$subjects{$subjectId}->{'visits'}->{$aVisitNum}->{'aVisit'}        = $aVisit if $aVisit;
			$subjects{$subjectId}->{'visits'}->{$aVisitNum}->{'visitDate'}     = $visitDate;
			$subjects{$subjectId}->{'visits'}->{$aVisitNum}->{'visitDatetime'} = $adtDatetime;
			$subjects{$subjectId}->{'totalAdvaRows'}++;

		}
	}
	close $in;
	close $outDouble;
	$dRNum--;
	say "dRNum       : $dRNum";
	say "noDose1Data : $noDose1Data";
	say "patients    : " . keys %subjects;
	# p%subjects;
	# die;
}

my $outputFolder   = "tasks/pfizer_trials/amyloidosis/adlb";
make_path($outputFolder) unless (-d $outputFolder);

# Prints patients .CSV.
open my $out, '>:utf8', 'tasks/pfizer_trials/amyloidosis/adlb.csv';
say $out "subjectId;cohort;aVisitNum;visitDatetime;param;avaLc;";
for my $subjectId (sort{$a <=> $b} keys %subjects) {
	my $cohort = $subjects{$subjectId}->{'cohort'} // die;
	for my $aVisitNum (sort{$a <=> $b} keys %{$subjects{$subjectId}->{'visits'}}) {
		my $aVisit   = $subjects{$subjectId}->{'visits'}->{$aVisitNum}->{'aVisit'} // die;
		my $visitDatetime = $subjects{$subjectId}->{'visits'}->{$aVisitNum}->{'visitDatetime'} // die;
		# p$subjects{$subjectId}->{'visits'};
		for my $param (sort keys %{$subjects{$subjectId}->{'visits'}->{$aVisitNum}->{'tests'}}) {
			my $avaLc = $subjects{$subjectId}->{'visits'}->{$aVisitNum}->{'tests'}->{$param} // die;
			say $out "$subjectId;$cohort;$aVisitNum;$visitDatetime;$param;$avaLc;";

		}
	}
}
close $out;