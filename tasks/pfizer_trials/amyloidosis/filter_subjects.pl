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
use Getopt::Long;

my $dt19600101    = '1960-01-01 12:00:00';
my $tp19600101    = time::datetime_to_timestamp($dt19600101);
my $dataFolder    = 'raw_data/pfizer_trials/xpt_files_to_csv';
my $adlbFile      = "$dataFolder/FDA-CBER-2021-5683-0652981-0654506-125742_S1_M5_bnt162-01-A-D-adlb.csv";
my %subjects      = ();
my $dataCsv       = Text::CSV_XS->new ({ binary => 1 });
my %visitsData    = ();

my ($cohortAnalysis, $subjectAnalysis) = (0, 0);
GetOptions(
    "cohort"  => \$cohortAnalysis,
    "subject" => \$subjectAnalysis
);
if (!$cohortAnalysis && !$subjectAnalysis) {
    print "No arguments provided.\n";
    exit;
}

my %paramsAnalyzed   = ();
config_params();

my %subjectsAnalyzed = ();
if ($subjectAnalysis) {
	config_subjects();
}

my %cohortsAnalyzed  = ();
if ($cohortAnalysis) {
	config_cohort();
}

my %paramsEquivalences = ();
load_parameters_equiv();

my $cohortsFiltered  = keys %cohortsAnalyzed;
my $subjectsFiltered = keys %subjectsAnalyzed;
my $paramsFiltered   = keys %paramsAnalyzed;
say "Filtering data on $cohortsFiltered cohorts, $subjectsFiltered subjects and $paramsFiltered parameters";

parse_adlb();


sub parse_adlb {
	say "parsing ADLB ...";
	my %dataLabels       = ();
	my ($dRNum,
		$expectedValues) = (0, 0);
	open my $in, '<:utf8', $adlbFile;
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

			# Fetching the data we currently focus on.
			my $subjectId      = $values{'SUBJID'}  // die;
			my $uSubjectId     = $values{'USUBJID'} // die;
			my $adt            = $values{'ADT'}     // die;
			$adt               = $tp19600101 + $adt * 86400;
			my $adtDatetime    = time::timestamp_to_datetime($adt);
			my ($visitDate)    = split ' ', $adtDatetime;
			$visitDate         =~ s/\D//g;
			my $age            = $values{'AGE'}     // die;
			my $sex            = $values{'SEX'}     // die;
			($age)             = split '\.', $age;
			my $ageUnit        = $values{'AGEU'}    // die;
			die unless $ageUnit eq 'YEARS';
			my $aVisit         = $values{'AVISIT'}  // die;
			my $aVisitNum      = $values{'AVISITN'} // die;
			($aVisitNum)       = split '\.', $aVisitNum;
			my $cohort         = $values{'COHORT'}  // die;
			my $param          = $values{'PARAM'}   // die;
			my $avaLc          = $values{'AVALC'}   // die;
			my ($siteCode)     = $uSubjectId =~ /........ (....) ......../;
			my $dose1Timestamp = $values{'TRTSDTM'} // die;
			my $dose1Datetime  = time::sas_timestamp_to_datetime($dose1Timestamp);
			my $d1cp = $dose1Datetime;
			$d1cp =~ s/\D//g;
			my $vcp = $adtDatetime;
			$vcp =~ s/\D//g;
			my $daysToDose1    = time::calculate_days_difference($adtDatetime, $dose1Datetime);
			if ($vcp < $d1cp) {
				$daysToDose1 = "-$daysToDose1";
			}
			if (exists $paramsEquivalences{$param}) {
				$param = $paramsEquivalences{$param} // die;
			}
			next unless $avaLc && looks_like_number $avaLc;
			if ($subjectAnalysis) {
				next unless exists $subjectsAnalyzed{$subjectId};
			}
			if ($cohortAnalysis) {
				next unless exists $cohortsAnalyzed{$cohort};
			}
			$subjects{$subjectId}->{'visits'}->{$aVisitNum}->{'tests'}->{$param}->{'avaLc'} = $avaLc;
			$subjects{$subjectId}->{'cohort'}          = $cohort;
			$subjects{$subjectId}->{'subjectId'}       = $subjectId;
			$subjects{$subjectId}->{'uSubjectId'}      = $uSubjectId;
			$subjects{$subjectId}->{'uSubjectIds'}->{$uSubjectId} = 1;
			$subjects{$subjectId}->{'sex'}             = $sex;
			$subjects{$subjectId}->{'age'}             = $age;
			$subjects{$subjectId}->{'dose1Datetime'}   = $dose1Datetime;
			$subjects{$subjectId}->{'visits'}->{$aVisitNum}->{'daysToDose1'}   = $daysToDose1;
			$subjects{$subjectId}->{'visits'}->{$aVisitNum}->{'aVisit'}        = $aVisit      if $aVisit;
			$subjects{$subjectId}->{'visits'}->{$aVisitNum}->{'visitDate'}     = $visitDate;
			$subjects{$subjectId}->{'visits'}->{$aVisitNum}->{'visitDatetime'} = $adtDatetime;
			$subjects{$subjectId}->{'totalAdvaRows'}++;

		}
	}
	close $in;
	$dRNum--;
	say "dRNum       : $dRNum";
	say "subjects    : " . keys %subjects;
}

open my $out, '>:utf8', 'filtered_subjects.csv';
say $out "cohort;subjectId;aVisitNum;daysToDose1;visitDatetime;param;avaLc;";
for my $subjectId (sort{$a <=> $b} keys %subjects) {
	my $cohort = $subjects{$subjectId}->{'cohort'} // die;
	for my $aVisitNum (sort{$a <=> $b} keys %{$subjects{$subjectId}->{'visits'}}) {
		my $daysToDose1 = $subjects{$subjectId}->{'visits'}->{$aVisitNum}->{'daysToDose1'} // die;
		my $visitDatetime = $subjects{$subjectId}->{'visits'}->{$aVisitNum}->{'visitDatetime'} // die;
		for my $param (sort keys %{$subjects{$subjectId}->{'visits'}->{$aVisitNum}->{'tests'}}) {
			my $avaLc = $subjects{$subjectId}->{'visits'}->{$aVisitNum}->{'tests'}->{$param}->{'avaLc'} // die;
			say $out "$cohort;$subjectId;$aVisitNum;$daysToDose1;$visitDatetime;$param;$avaLc;";
		}
	}
}
close $out;



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

sub config_params {
	$paramsAnalyzed{'Alanine Aminotransferase [U/L]'} = 1;
	$paramsAnalyzed{'Albumin [g/L]'} = 1;
	$paramsAnalyzed{'Alkaline Phosphatase [U/L]'} = 1;
	$paramsAnalyzed{'Amylase [U/L]'} = 1;
	$paramsAnalyzed{'Aspartate Aminotransferase [U/L]'} = 1;
	$paramsAnalyzed{'Basophils (Blood Smear) [10^9/L]'} = 1;
	$paramsAnalyzed{'Basophils/Leukocytes (Blood Smear) [%]'} = 1;
	$paramsAnalyzed{'Basophils/Leukocytes (Blood) [%]'} = 1;
	$paramsAnalyzed{'Bilirubin (Serum) [umol/L]'} = 1;
	$paramsAnalyzed{'Bilirubin (Urine) [umol/L]'} = 1;
	$paramsAnalyzed{'C Reactive Protein [mg/L]'} = 1;
	$paramsAnalyzed{'Calcium [mmol/L]'} = 1;
	$paramsAnalyzed{'Creatine Kinase [U/L]'} = 1;
	$paramsAnalyzed{'Creatinine [umol/L]'} = 1;
	$paramsAnalyzed{'Eosinophils (Blood Smear) [10^9/L]'} = 1;
	$paramsAnalyzed{'Eosinophils/Leukocytes (Blood Smear) [%]'} = 1;
	$paramsAnalyzed{'Eosinophils/Leukocytes (Blood) [%]'} = 1;
	$paramsAnalyzed{'Ery. Mean Corpuscular HGB Concentration [mmol/L]'} = 1;
	$paramsAnalyzed{'Ery. Mean Corpuscular Hemoglobin [fmol]'} = 1;
	$paramsAnalyzed{'Ery. Mean Corpuscular Volume [fL]'} = 1;
	$paramsAnalyzed{'Erythrocytes (Blood) [10^12/L]'} = 1;
	$paramsAnalyzed{'Ferritin [ug/L]'} = 1;
	$paramsAnalyzed{'Follicle Stimulating Hormone [IU/L]'} = 1;
	$paramsAnalyzed{'Gamma Glutamyl Transferase [U/L]'} = 1;
	$paramsAnalyzed{'Glucose (Blood) [mmol/L]'} = 1;
	$paramsAnalyzed{'Granulocytes Band Form/Total Cells [%]'} = 1;
	$paramsAnalyzed{'Hematocrit [L/L]'} = 1;
	$paramsAnalyzed{'Hemoglobin (Blood) [mmol/L]'} = 1;
	$paramsAnalyzed{'Hemoglobin (Urine) [10^6/L]'} = 1;
	$paramsAnalyzed{'Ketones [mmol/L]'} = 1;
	$paramsAnalyzed{'Leukocytes (Blood) [10^9/L]'} = 1;
	$paramsAnalyzed{'Leukocytes (Urine - Dipstick) [10^6/L]'} = 1;
	$paramsAnalyzed{'Lipase [U/L]'} = 1;
	$paramsAnalyzed{'Lymphocytes (Blood Smear) [10^9/L]'} = 1;
	$paramsAnalyzed{'Lymphocytes Atypical/Leukocytes [%]'} = 1;
	$paramsAnalyzed{'Lymphocytes/Leukocytes (Blood Smear) [%]'} = 1;
	$paramsAnalyzed{'Lymphocytes/Leukocytes (Blood) [%]'} = 1;
	$paramsAnalyzed{'Monocytes (Blood Smear) [10^9/L]'} = 1;
	$paramsAnalyzed{'Monocytes/Leukocytes (Blood Smear) [%]'} = 1;
	$paramsAnalyzed{'Monocytes/Leukocytes (Blood) [%]'} = 1;
	$paramsAnalyzed{'Myelocytes [%]'} = 1;
	$paramsAnalyzed{'Neutrophils (Blood Smear) [10^9/L]'} = 1;
	$paramsAnalyzed{'Neutrophils/Leukocytes (Blood Smear) [%]'} = 1;
	$paramsAnalyzed{'Neutrophils/Leukocytes (Blood) [%]'} = 1;
	$paramsAnalyzed{'Platelets [10^9/L]'} = 1;
	$paramsAnalyzed{'Potassium [mmol/L]'} = 1;
	$paramsAnalyzed{'Protein [mg/L]'} = 1;
	$paramsAnalyzed{'Smudge Cells/Leukocytes [%]'} = 1;
	$paramsAnalyzed{'Sodium [mmol/L]'} = 1;
	$paramsAnalyzed{'Specific Gravity'} = 1;
	$paramsAnalyzed{'Urea Nitrogen [mmol/L]'} = 1;
	$paramsAnalyzed{'Urobilinogen [umol/L]'} = 1;
	$paramsAnalyzed{'pH'} = 1;
}

sub config_subjects {
	$subjectsAnalyzed{'10001'} = 1;
	$subjectsAnalyzed{'10003'} = 1;
	$subjectsAnalyzed{'10004'} = 1;
	$subjectsAnalyzed{'10005'} = 1;
	$subjectsAnalyzed{'10006'} = 1;
	$subjectsAnalyzed{'10007'} = 1;
	$subjectsAnalyzed{'10008'} = 1;
	$subjectsAnalyzed{'10009'} = 1;
	$subjectsAnalyzed{'10010'} = 1;
	$subjectsAnalyzed{'10011'} = 1;
	$subjectsAnalyzed{'10015'} = 1;
	$subjectsAnalyzed{'10016'} = 1;
	$subjectsAnalyzed{'10017'} = 1;
	$subjectsAnalyzed{'10018'} = 1;
	$subjectsAnalyzed{'10019'} = 1;
	$subjectsAnalyzed{'10020'} = 1;
	$subjectsAnalyzed{'10021'} = 1;
	$subjectsAnalyzed{'10023'} = 1;
	$subjectsAnalyzed{'10025'} = 1;
	$subjectsAnalyzed{'10028'} = 1;
	$subjectsAnalyzed{'10031'} = 1;
	$subjectsAnalyzed{'10032'} = 1;
	$subjectsAnalyzed{'10033'} = 1;
	$subjectsAnalyzed{'10034'} = 1;
	$subjectsAnalyzed{'10036'} = 1;
	$subjectsAnalyzed{'10037'} = 1;
	$subjectsAnalyzed{'10038'} = 1;
	$subjectsAnalyzed{'10039'} = 1;
	$subjectsAnalyzed{'10040'} = 1;
	$subjectsAnalyzed{'10041'} = 1;
	$subjectsAnalyzed{'10042'} = 1;
	$subjectsAnalyzed{'10043'} = 1;
	$subjectsAnalyzed{'10045'} = 1;
	$subjectsAnalyzed{'10047'} = 1;
	$subjectsAnalyzed{'10048'} = 1;
	$subjectsAnalyzed{'10049'} = 1;
	$subjectsAnalyzed{'10050'} = 1;
	$subjectsAnalyzed{'10052'} = 1;
	$subjectsAnalyzed{'10053'} = 1;
	$subjectsAnalyzed{'10055'} = 1;
	$subjectsAnalyzed{'10056'} = 1;
	$subjectsAnalyzed{'10057'} = 1;
	$subjectsAnalyzed{'10059'} = 1;
	$subjectsAnalyzed{'10060'} = 1;
	$subjectsAnalyzed{'10066'} = 1;
	$subjectsAnalyzed{'10067'} = 1;
	$subjectsAnalyzed{'10068'} = 1;
	$subjectsAnalyzed{'10070'} = 1;
	$subjectsAnalyzed{'10073'} = 1;
	$subjectsAnalyzed{'10075'} = 1;
	$subjectsAnalyzed{'10076'} = 1;
	$subjectsAnalyzed{'10078'} = 1;
	$subjectsAnalyzed{'10083'} = 1;
	$subjectsAnalyzed{'10084'} = 1;
	$subjectsAnalyzed{'10085'} = 1;
	$subjectsAnalyzed{'10089'} = 1;
	$subjectsAnalyzed{'10093'} = 1;
	$subjectsAnalyzed{'10096'} = 1;
	$subjectsAnalyzed{'10103'} = 1;
	$subjectsAnalyzed{'10104'} = 1;
	$subjectsAnalyzed{'10151'} = 1;
	$subjectsAnalyzed{'10170'} = 1;
	$subjectsAnalyzed{'10171'} = 1;
	$subjectsAnalyzed{'10172'} = 1;
	$subjectsAnalyzed{'10173'} = 1;
	$subjectsAnalyzed{'10175'} = 1;
	$subjectsAnalyzed{'10176'} = 1;
	$subjectsAnalyzed{'10178'} = 1;
	$subjectsAnalyzed{'10179'} = 1;
	$subjectsAnalyzed{'10181'} = 1;
	$subjectsAnalyzed{'10182'} = 1;
	$subjectsAnalyzed{'10183'} = 1;
	$subjectsAnalyzed{'10194'} = 1;
	$subjectsAnalyzed{'10197'} = 1;
	$subjectsAnalyzed{'10198'} = 1;
	$subjectsAnalyzed{'10200'} = 1;
	$subjectsAnalyzed{'10204'} = 1;
	$subjectsAnalyzed{'10209'} = 1;
	$subjectsAnalyzed{'10212'} = 1;
	$subjectsAnalyzed{'10221'} = 1;
	$subjectsAnalyzed{'10224'} = 1;
	$subjectsAnalyzed{'10225'} = 1;
	$subjectsAnalyzed{'10226'} = 1;
	$subjectsAnalyzed{'10227'} = 1;
	$subjectsAnalyzed{'10261'} = 1;
	$subjectsAnalyzed{'10263'} = 1;
	$subjectsAnalyzed{'10265'} = 1;
	$subjectsAnalyzed{'10267'} = 1;
	$subjectsAnalyzed{'10268'} = 1;
	$subjectsAnalyzed{'10269'} = 1;
	$subjectsAnalyzed{'10272'} = 1;
	$subjectsAnalyzed{'10273'} = 1;
	$subjectsAnalyzed{'10274'} = 1;
	$subjectsAnalyzed{'10275'} = 1;
	$subjectsAnalyzed{'10276'} = 1;
	$subjectsAnalyzed{'10277'} = 1;
	$subjectsAnalyzed{'10279'} = 1;
	$subjectsAnalyzed{'10282'} = 1;
	$subjectsAnalyzed{'10283'} = 1;
	$subjectsAnalyzed{'10286'} = 1;
	$subjectsAnalyzed{'10287'} = 1;
	$subjectsAnalyzed{'10288'} = 1;
	$subjectsAnalyzed{'10289'} = 1;
	$subjectsAnalyzed{'10291'} = 1;
	$subjectsAnalyzed{'10292'} = 1;
	$subjectsAnalyzed{'10298'} = 1;
	$subjectsAnalyzed{'10299'} = 1;
	$subjectsAnalyzed{'10300'} = 1;
	$subjectsAnalyzed{'10303'} = 1;
	$subjectsAnalyzed{'10305'} = 1;
	$subjectsAnalyzed{'10306'} = 1;
	$subjectsAnalyzed{'10308'} = 1;
	$subjectsAnalyzed{'10309'} = 1;
	$subjectsAnalyzed{'10310'} = 1;
	$subjectsAnalyzed{'10314'} = 1;
	$subjectsAnalyzed{'10316'} = 1;
	$subjectsAnalyzed{'10319'} = 1;
	$subjectsAnalyzed{'10320'} = 1;
	$subjectsAnalyzed{'10323'} = 1;
	$subjectsAnalyzed{'10324'} = 1;
	$subjectsAnalyzed{'10350'} = 1;
	$subjectsAnalyzed{'10351'} = 1;
	$subjectsAnalyzed{'10352'} = 1;
	$subjectsAnalyzed{'10353'} = 1;
	$subjectsAnalyzed{'10358'} = 1;
	$subjectsAnalyzed{'10360'} = 1;
	$subjectsAnalyzed{'10361'} = 1;
	$subjectsAnalyzed{'10362'} = 1;
	$subjectsAnalyzed{'10363'} = 1;
	$subjectsAnalyzed{'10364'} = 1;
	$subjectsAnalyzed{'10365'} = 1;
	$subjectsAnalyzed{'10366'} = 1;
	$subjectsAnalyzed{'20101'} = 1;
	$subjectsAnalyzed{'20102'} = 1;
	$subjectsAnalyzed{'20103'} = 1;
	$subjectsAnalyzed{'20104'} = 1;
	$subjectsAnalyzed{'20105'} = 1;
	$subjectsAnalyzed{'20110'} = 1;
	$subjectsAnalyzed{'20111'} = 1;
	$subjectsAnalyzed{'20114'} = 1;
	$subjectsAnalyzed{'20116'} = 1;
	$subjectsAnalyzed{'20117'} = 1;
	$subjectsAnalyzed{'20118'} = 1;
	$subjectsAnalyzed{'20121'} = 1;
	$subjectsAnalyzed{'20127'} = 1;
	$subjectsAnalyzed{'20128'} = 1;
	$subjectsAnalyzed{'20134'} = 1;
	$subjectsAnalyzed{'20137'} = 1;
	$subjectsAnalyzed{'20138'} = 1;
	$subjectsAnalyzed{'20142'} = 1;
	$subjectsAnalyzed{'20143'} = 1;
	$subjectsAnalyzed{'20144'} = 1;
	$subjectsAnalyzed{'20145'} = 1;
	$subjectsAnalyzed{'20149'} = 1;
	$subjectsAnalyzed{'20150'} = 1;
	$subjectsAnalyzed{'20153'} = 1;
	$subjectsAnalyzed{'20154'} = 1;
	$subjectsAnalyzed{'20155'} = 1;
	$subjectsAnalyzed{'20156'} = 1;
	$subjectsAnalyzed{'20157'} = 1;
	$subjectsAnalyzed{'20158'} = 1;
	$subjectsAnalyzed{'20159'} = 1;
	$subjectsAnalyzed{'20160'} = 1;
	$subjectsAnalyzed{'20163'} = 1;
	$subjectsAnalyzed{'20164'} = 1;
	$subjectsAnalyzed{'20166'} = 1;
	$subjectsAnalyzed{'20168'} = 1;
	$subjectsAnalyzed{'20171'} = 1;
	$subjectsAnalyzed{'20172'} = 1;
	$subjectsAnalyzed{'20173'} = 1;
	$subjectsAnalyzed{'20174'} = 1;
	$subjectsAnalyzed{'20175'} = 1;
	$subjectsAnalyzed{'20176'} = 1;
	$subjectsAnalyzed{'20177'} = 1;
	$subjectsAnalyzed{'20178'} = 1;
	$subjectsAnalyzed{'20179'} = 1;
	$subjectsAnalyzed{'20180'} = 1;
	$subjectsAnalyzed{'20181'} = 1;
	$subjectsAnalyzed{'20183'} = 1;
	$subjectsAnalyzed{'20185'} = 1;
	$subjectsAnalyzed{'20188'} = 1;
	$subjectsAnalyzed{'20189'} = 1;
	$subjectsAnalyzed{'20191'} = 1;
	$subjectsAnalyzed{'20192'} = 1;
	$subjectsAnalyzed{'20193'} = 1;
	$subjectsAnalyzed{'20194'} = 1;
	$subjectsAnalyzed{'20195'} = 1;
	$subjectsAnalyzed{'20197'} = 1;
	$subjectsAnalyzed{'20200'} = 1;
	$subjectsAnalyzed{'20201'} = 1;
	$subjectsAnalyzed{'20203'} = 1;
	$subjectsAnalyzed{'20204'} = 1;
	$subjectsAnalyzed{'20207'} = 1;
	$subjectsAnalyzed{'20208'} = 1;
	$subjectsAnalyzed{'20211'} = 1;
	$subjectsAnalyzed{'20214'} = 1;
	$subjectsAnalyzed{'20215'} = 1;
	$subjectsAnalyzed{'20216'} = 1;
	$subjectsAnalyzed{'20220'} = 1;
	$subjectsAnalyzed{'20221'} = 1;
	$subjectsAnalyzed{'20222'} = 1;
	$subjectsAnalyzed{'20223'} = 1;
	$subjectsAnalyzed{'20224'} = 1;
	$subjectsAnalyzed{'20225'} = 1;
	$subjectsAnalyzed{'20226'} = 1;
	$subjectsAnalyzed{'20227'} = 1;
	$subjectsAnalyzed{'20229'} = 1;
	$subjectsAnalyzed{'20233'} = 1;
	$subjectsAnalyzed{'20234'} = 1;
	$subjectsAnalyzed{'20236'} = 1;
	$subjectsAnalyzed{'20237'} = 1;
	$subjectsAnalyzed{'20238'} = 1;
	$subjectsAnalyzed{'20239'} = 1;
	$subjectsAnalyzed{'20241'} = 1;
	$subjectsAnalyzed{'20242'} = 1;
	$subjectsAnalyzed{'20243'} = 1;
}

sub config_cohort {
	$cohortsAnalyzed{'Cohort 1'}  = 1;
	$cohortsAnalyzed{'Cohort 2'}  = 1;
	$cohortsAnalyzed{'Cohort 3'}  = 1;
	$cohortsAnalyzed{'Cohort 4'}  = 1;
	$cohortsAnalyzed{'Cohort 5'}  = 1;
	$cohortsAnalyzed{'Cohort 6'}  = 1;
	$cohortsAnalyzed{'Cohort 7'}  = 1;
	$cohortsAnalyzed{'Cohort 8'}  = 1;
	$cohortsAnalyzed{'Cohort 9'}  = 1;
	$cohortsAnalyzed{'Cohort 10'} = 1;
}