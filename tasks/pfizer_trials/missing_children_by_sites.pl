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
my $suppdsFile   = 'raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0171524-to-0174606_125742_S1_M5_c4591001-S-D-suppds.csv';
die "you must convert the suppds file using readstats and place it in [raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0123168-to-0126026_125742_S1_M5_c4591001-A-D-suppds.csv] first." unless -f $suppdsFile;
open my $in, '<:utf8', $suppdsFile;
my $dataCsv      = Text::CSV_XS->new ({ binary => 1 });
my %dataLabels   = ();
my ($dRNum,
	$expectedValues,
	$screeningOrder) = (0, 0, 0, 0);
my %subjects      = ();
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
		my $uSubjectId  = $values{'USUBJID'} // die;
		my ($subjectId) = $uSubjectId =~ /C4591001 \d\d\d\d (\d\d\d\d\d\d\d\d)/;
		my $qval        = $values{'QVAL'}    // die;
		next unless $qval eq 'SCREENING';
		$screeningOrder++;
		my ($trialSiteId) = $subjectId =~ /(....)..../;
		$subjects{$trialSiteId}->{$subjectId} = $screeningOrder;
	}
}
close $in;
say "dRNum       : $dRNum";

my $addvFile          = "public/doc/pfizer_trials/pfizer_addv_patients.json";
my %addvData = ();
addv_data();
my $randomizationFile = "public/doc/pfizer_trials/pfizer_trial_randomizations_merged.json";
my $allFilesFile      = "public/doc/pfizer_trials/pfizer_sas_data_patients.json";
my $advaFile          = "public/doc/pfizer_trials/pfizer_adva_patients.json";
my %advaData = ();
my %sites    = ();
my %randomizationData = ();
my %allFilesData      = ();
randomization_data();  # Loads the JSON formatted randomization data.
all_files_data();      # Loads the JSON formatted files summary data.
adva_data();
my %randomization    = ();
my $randoMergedFile  = 'public/doc/pfizer_trials/merged_doses_data.json';
load_randomization();
my %xptData = ();
load_xpt_data();
my %pdfData = ();
load_pdf_data();

sub addv_data {
	open my $in, '<:utf8', $addvFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%addvData = %$json;
}

sub load_xpt_data {
	my $xptDataFile = 'public/doc/pfizer_trials/pfizer_sas_data_patients.json';
	open my $in, '<:utf8', $xptDataFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%xptData = %$json;
}

sub load_pdf_data {
	my $pdfDataFile = 'public/doc/pfizer_trials/pfizer_pdf_data_patients.json';
	open my $in, '<:utf8', $pdfDataFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%pdfData = %$json;
}

sub load_randomization {
	open my $in, '<:utf8', $randoMergedFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%randomization = %$json;
	say "[$randoMergedFile] -> patients : " . keys %randomization;
}

my %stats = ();
for my $subjectId (sort keys %advaData) {
	$stats{'totalPatients'}++;
	my $trialSiteId   = $advaData{$subjectId}->{'trialSiteId'} // die;
	my $uSubjectId    = $advaData{$subjectId}->{'uSubjectId'} // die;
	die unless exists $allFilesData{'subjects'}->{$subjectId};
	# 1st Dose.
	my $age = $advaData{$subjectId}->{'age'} // die;
	next unless $age < 16;
	$stats{'all_subjects'}->{$subjectId} = 1;
	$sites{$trialSiteId} = 1;
	# p$advaData{$subjectId};
	# die;
}

say "sites    ---> " . keys %sites;
say "subjects ---> " . keys %{$stats{'all_subjects'}};
# p%sites;

open my $out1, '>:utf8', 'missing_children_by_sites.csv';
say $out1 "Trial Site ID;Subject ID;Age;Has Exclusion;";
for my $trialSiteId (sort{$a <=> $b} keys %sites) {
	die unless exists $subjects{$trialSiteId};
	for my $subjectId (sort{$a <=> $b} keys %{$subjects{$trialSiteId}}) {
		unless (exists $randomization{$subjectId}) {
			$stats{'totalNonRandomized'}++;
			$stats{'totalNonRandomizedNoXpt'}++ unless exists $xptData{'subjects'}->{$subjectId};
			unless (exists $pdfData{'subjects'}->{$subjectId}) {
				$stats{'totalNonRandomizedNoPdf'}++;
			} else {
				my $age          = $advaData{$subjectId}->{'age'} // $addvData{$subjectId}->{'age'} // 'NA';
				my $hasExclusion = 0;
				$hasExclusion    = 1 if $addvData{$subjectId};
				say $out1 "$trialSiteId;$subjectId;$age;$hasExclusion;";
				# say "[$trialSiteId] - Subject [$subjectId] hasn't been randomized";
				$stats{'suspectedOfInterest'}->{'totals'}++;
				$stats{'suspectedOfInterest'}->{'bySites'}->{$trialSiteId}++;
				# p$xptData{'subjects'}->{$subjectId};
				# p$pdfData{'subjects'}->{$subjectId};
			}
		}
	}
}
close $out1;
delete $stats{'all_subjects'};
p%stats;

sub randomization_data {
	my $json;
	open my $in, '<:utf8', $randomizationFile;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%randomizationData = %$json;
	say "[$randomizationFile] -> subjects : " . keys %randomizationData;
}

sub all_files_data {
	my $json;
	open my $in, '<:utf8', $allFilesFile;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%allFilesData = %$json;
	say "[$allFilesFile] -> subjects : " . keys %{$allFilesData{'subjects'}};
}

sub adva_data {
	open my $in, '<:utf8', $advaFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%advaData = %$json;
}