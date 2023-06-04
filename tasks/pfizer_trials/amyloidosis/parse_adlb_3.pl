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
my %params        = ();
my %visitsData    = ();

my %paramsEquivalences = ();

load_parameters_equiv();

sub load_parameters_equiv {
	open my $in, '<:utf8', 'tasks/pfizer_trials/amyloidosis/params_equivalence.csv';
	die unless -f 'tasks/pfizer_trials/amyloidosis/params_equivalence.csv';
	while (<$in>) {
		chomp $_;
		my ($param1, $param2) = split ';', $_;
		$paramsEquivalences{$param1} = $param2;
	}
	close $in;
}
# p%paramsEquivalences;
# die;

parse_adlb();
p%params;
say "Total parameters : " . keys %params;
say "Total subjects   : " . keys %subjects;


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
	# open my $out, '>:utf8', 'tasks/pfizer_trials/amyloidosis/adlb_test_differences.csv';
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
				# say "No randomization data";
				$noDose1Data++;
				next;
				p%values;
				die "dose1Timestamp : [$dose1Timestamp]";
			}
			my $dose1Datetime  = time::sas_timestamp_to_datetime($dose1Timestamp);
			my $d1cp = $dose1Datetime;
			$d1cp =~ s/\D//g;
			my $vcp = $adtDatetime;
			$vcp =~ s/\D//g;
			my $daysToDose1    = time::calculate_days_difference($adtDatetime, $dose1Datetime);
			if ($vcp < $d1cp) {
				$daysToDose1 = "-$daysToDose1";
			}
			# say "--> dose1Datetime  : $dose1Datetime";
			# say "--> dose1Datetime          : $dose1Datetime";
			# if (exists $subjects{$subjectId}->{'visits'}->{$aVisitNum}->{'tests'}->{$param}) {
			# 	if ($subjects{$subjectId}->{'visits'}->{$aVisitNum}->{'tests'}->{$param} ne $avaLc) {
			# 		my $old = $subjects{$subjectId}->{'visits'}->{$aVisitNum}->{'tests'}->{$param} // die;
			# 		say $out "$subjectId;$aVisitNum;$aVisit;$param;$old;$avaLc;";
			# 		# p$subjects{$subjectId}->{'visits'}->{$aVisitNum};
			# 		# say "param : $param";
			# 		# say "avaLc : $avaLc";
			# 		# die;
			# 	}
			# 	# die unless $subjects{$subjectId}->{'visits'}->{$aVisitNum}->{'visitDate'} eq $visitDate;
			# }
			# if (
			# 	$param eq 'Lymphocytes/Leukocytes (Blood) [%]' ||
			# 	$param eq 'Lymphocytes (Blood) [10^9/L]'
			# ) {
			# 	# p%values;
			# 	my %o = ();
			# 	$o{'avaLc'}     = $avaLc;
			# 	$o{'aVisit'}    = $aVisit;
			# 	$o{'aVisitNum'} = $aVisitNum;
			# 	if (!$aVisit) {
			# 		die if exists $subjects{$subjectId}->{'visits'}->{$aVisitNum}->{'tests'}->{$param}; # This verifies that no incremental entry for the same test has
			# 																							# been made before when the "AVISIT" scalar is empty.
			# 	}
			# 	$subjects{$subjectId}->{'visits'}->{$aVisitNum}->{'tests'}->{$param} = $avaLc;
			# } else {
			# 	next;
			# }
			if (exists $paramsEquivalences{$param}) {
				$param = $paramsEquivalences{$param} // die;
			}
			next unless $avaLc && looks_like_number $avaLc;
			$param =~ s/\W//g;
			$subjects{$param}->{$cohort}->{$subjectId}->{'visits'}->{$aVisitNum}->{'avaLc'} = $avaLc;
			$subjects{$param}->{$cohort}->{$subjectId}->{'cohort'}          = $cohort;
			$subjects{$param}->{$cohort}->{$subjectId}->{'subjectId'}       = $subjectId;
			$subjects{$param}->{$cohort}->{$subjectId}->{'uSubjectId'}      = $uSubjectId;
			$subjects{$param}->{$cohort}->{$subjectId}->{'uSubjectIds'}->{$uSubjectId} = 1;
			$subjects{$param}->{$cohort}->{$subjectId}->{'sex'}             = $sex;
			$subjects{$param}->{$cohort}->{$subjectId}->{'age'}             = $age;
			$subjects{$param}->{$cohort}->{$subjectId}->{'dose1Datetime'}   = $dose1Datetime;
			$subjects{$param}->{$cohort}->{$subjectId}->{'visits'}->{$aVisitNum}->{'daysToDose1'}   = $daysToDose1;
			$subjects{$param}->{$cohort}->{$subjectId}->{'visits'}->{$aVisitNum}->{'aVisit'}        = $aVisit      if $aVisit;
			$subjects{$param}->{$cohort}->{$subjectId}->{'visits'}->{$aVisitNum}->{'visitDate'}     = $visitDate;
			$subjects{$param}->{$cohort}->{$subjectId}->{'visits'}->{$aVisitNum}->{'visitDatetime'} = $adtDatetime;
			$subjects{$param}->{$cohort}->{$subjectId}->{'totalAdvaRows'}++;

		}
	}
	close $in;
	$dRNum--;
	say "dRNum       : $dRNum";
	say "noDose1Data : $noDose1Data";
	say "patients    : " . keys %subjects;
	# close $out;
	# p%subjects;
	# die;
}


for my $param (sort keys %subjects) {
	for my $cohort (sort keys %{$subjects{$param}}) {
		my $outputFolder   = "tasks/pfizer_trials/amyloidosis/adlb_by_param/$cohort";
		make_path($outputFolder) unless (-d $outputFolder);
		# Prints patients .CSV.
		open my $out, '>:utf8', "tasks/pfizer_trials/amyloidosis/adlb_by_param/$cohort/$param.csv";
		say $out "subjectId;aVisitNum;avaLc;";
		for my $subjectId (sort{$a <=> $b} keys %{$subjects{$param}->{$cohort}}) {
			for my $aVisitNum (sort{$a <=> $b} keys %{$subjects{$param}->{$cohort}->{$subjectId}->{'visits'}}) {
				my $daysToDose1 = $subjects{$param}->{$cohort}->{$subjectId}->{'visits'}->{$aVisitNum}->{'daysToDose1'} // die;
				my $visitDatetime = $subjects{$param}->{$cohort}->{$subjectId}->{'visits'}->{$aVisitNum}->{'visitDatetime'} // die;
				my $avaLc = $subjects{$param}->{$cohort}->{$subjectId}->{'visits'}->{$aVisitNum}->{'avaLc'} // die;
				say $out "$subjectId;$aVisitNum;$avaLc;";
			}
		}
		close $out;
	}
}

